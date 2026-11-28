import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';

import '../../shared/pose/angle_smoother.dart';
import '../../shared/pose/pose_math.dart';
import 'form/form_coach.dart';
import 'form/form_feedback.dart';
import 'form/frame_preprocess.dart' show modelInputSize;
import 'form/keypoint_landmarks.dart';
import 'form/posenet_engine.dart' show PoseNetOutput;
import 'form/posenet_worker.dart';
import 'workout_camera.dart';

/// Webcam on a computer. The Windows camera plugin cannot stream frames, so
/// this takes a still picture, runs the model on it, and repeats (about 2 per
/// second). The same model gives both the joint angles for scoring (keypoints)
/// and the form feedback (classifier), so no ML Kit is needed.
///
/// Pictures are written to disk by the plugin; each one is deleted as soon as
/// it has been read, and nothing leaves the machine.
class DesktopCamera implements WorkoutCamera {
  CameraController? _controller;
  PoseNetWorker? _worker;
  FormCoach? _coach;
  void Function(Map<Joint, double>)? _onAngles;
  bool _running = false;
  Future<void>? _loop;
  final _form = ValueNotifier<FormFeedback?>(null);
  final _smoother = AngleSmoother(alpha: 0.65, maxJumpDeg: 120.0);

  @override
  ValueListenable<FormFeedback?> get formFeedback => _form;

  @override
  bool get isOpen => _controller?.value.isInitialized ?? false;

  @override
  Future<void> open() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) throw const NoCameraException();
    // Many Windows webcams (e.g. 480p/720p-only HD cameras) fail preview init
    // when asked for ResolutionPreset.low (<=240p). Try medium first and fall
    // back across presets and cameras so any working webcam opens cleanly.
    CameraController? controller;
    Object? lastError;
    for (final camera in cameras) {
      for (final preset in const [
        ResolutionPreset.medium,
        ResolutionPreset.high,
        ResolutionPreset.max,
        ResolutionPreset.low,
      ]) {
        final candidate = CameraController(camera, preset, enableAudio: false);
        try {
          await candidate.initialize();
          controller = candidate;
          break;
        } catch (e) {
          lastError = e;
          await candidate.dispose().catchError((_) {});
        }
      }
      if (controller != null) break;
    }
    if (controller == null) {
      throw lastError ?? StateError('Failed to open camera');
    }
    _controller = controller;

    final posenet = await rootBundle.load(
      'assets/models/posenet_075_stride16.bin',
    );
    final head = await rootBundle.load('assets/models/form_head.bin');
    _worker = await PoseNetWorker.start(
      posenet.buffer.asUint8List(posenet.offsetInBytes, posenet.lengthInBytes),
      head.buffer.asUint8List(head.offsetInBytes, head.lengthInBytes),
    );
    final labels = await rootBundle.loadString(
      'assets/models/pose_labels.json',
    );
    _coach = FormCoach((jsonDecode(labels) as List<dynamic>).cast<String>());
  }

  @override
  double get previewAspect {
    final size = _controller?.value.previewSize;
    return size == null ? 16 / 9 : size.width / size.height;
  }

  @override
  Widget buildPreview() {
    final controller = _controller!;
    final size = controller.value.previewSize!;
    // Mirrored like a selfie view, which is also what the model was trained on.
    return ExcludeSemantics(
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: Transform.flip(
              flipX: true,
              child: CameraPreview(controller),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Future<void> startFrames(
    void Function(Map<Joint, double> angles) onAngles,
  ) async {
    _onAngles = onAngles;
    if (_running) return;
    _smoother.reset();
    _running = true;
    // Fail here (not silently later) if the first picture cannot be taken.
    final first = _captureAndAnalyse();
    await first;
    _loop = _run();
  }

  Future<void>? _inflight;

  Future<void> _run() async {
    var failures = 0;
    while (_running) {
      try {
        await _captureAndPipeline();
        failures = 0;
      } catch (_) {
        if (++failures >= 5) {
          _running = false;
          return;
        }
      }
    }
    await _inflight?.catchError((_) {});
    _inflight = null;
  }

  bool _busy = false;

  Future<void> _captureAndAnalyse() async {
    if (_busy) return;
    _busy = true;
    try {
      final frame = await _captureRgba();
      if (frame == null) return;
      final out = await _worker!.runRgba(
        frame.bytes,
        frame.width,
        frame.height,
        mirror: true,
      );
      _publish(out);
    } finally {
      _busy = false;
    }
  }

  /// Captures the next webcam frame while the previous frame's inference is
  /// still running on the worker isolate, overlapping I/O with neural net work.
  Future<void> _captureAndPipeline() async {
    final frame = await _captureRgba();
    if (!_running) return;
    await _inflight?.catchError((_) {});
    _inflight = null;
    if (frame == null || !_running) return;
    _inflight = _worker!
        .runRgba(frame.bytes, frame.width, frame.height, mirror: true)
        .then(_publish);
  }

  void _publish(PoseNetOutput out) {
    if (_onAngles == null) return;
    final raw = measureAngles(
      landmarksFromKeypoints(out.keypoints, mirrored: true),
    );
    if (raw.isNotEmpty) {
      final smoothed = _smoother.add(raw);
      if (smoothed.isNotEmpty) _onAngles?.call(smoothed);
    }
    _form.value = _coach!.update(out.probabilities);
  }

  Future<({Uint8List bytes, int width, int height})?> _captureRgba() async {
    final controller = _controller!;
    final shot = await controller.takePicture();
    final Uint8List bytes;
    try {
      bytes = await shot.readAsBytes();
    } finally {
      try {
        await File(shot.path).delete();
      } catch (_) {}
    }
    final preview = controller.value.previewSize;
    final portrait = preview != null && preview.height > preview.width;
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: portrait ? null : modelInputSize,
      targetHeight: portrait ? modelInputSize : null,
      allowUpscaling: false,
    );
    final image = (await codec.getNextFrame()).image;
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final width = image.width, height = image.height;
    image.dispose();
    codec.dispose();
    if (rgba == null) return null;
    return (
      bytes: rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
      width: width,
      height: height,
    );
  }

  @override
  Future<void> stopFrames() async {
    _running = false;
    _onAngles = null;
    await _loop?.catchError((_) {});
    _loop = null;
  }

  @override
  Future<void> close() async {
    _running = false;
    _onAngles = null;
    await _loop?.catchError((_) {});
    _worker?.close();
    _form.dispose();
    await _controller?.dispose();
  }
}
