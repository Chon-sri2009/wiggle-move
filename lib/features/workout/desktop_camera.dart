import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';

import '../../shared/pose/pose_math.dart';
import 'form/form_coach.dart';
import 'form/form_feedback.dart';
import 'form/frame_preprocess.dart';
import 'form/keypoint_landmarks.dart';
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

  @override
  ValueListenable<FormFeedback?> get formFeedback => _form;

  @override
  bool get isOpen => _controller?.value.isInitialized ?? false;

  @override
  Future<void> open() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) throw const NoCameraException();
    final controller = CameraController(
      cameras.first,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    _controller = controller;
    await controller.initialize();

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
    _running = true;
    // Fail here (not silently later) if the first picture cannot be taken.
    final first = _captureAndAnalyse();
    await first;
    _loop = _run();
  }

  Future<void> _run() async {
    var failures = 0;
    while (_running) {
      try {
        await _captureAndAnalyse();
        failures = 0;
      } catch (_) {
        if (++failures >= 5) {
          _running = false;
          return;
        }
      }
    }
  }

  bool _busy = false;

  Future<void> _captureAndAnalyse() async {
    if (_busy) return;
    _busy = true;
    try {
      await _captureAndAnalyseOnce();
    } finally {
      _busy = false;
    }
  }

  Future<void> _captureAndAnalyseOnce() async {
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
    final codec = await ui.instantiateImageCodec(bytes);
    final image = (await codec.getNextFrame()).image;
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final width = image.width, height = image.height;
    image.dispose();
    codec.dispose();
    if (rgba == null) return;

    final data = rgba.buffer.asUint8List(
      rgba.offsetInBytes,
      rgba.lengthInBytes,
    );
    final input = preprocessFrame(
      width: width,
      height: height,
      pixelAt: (x, y) {
        final i = (y * width + x) * 4;
        return (data[i] << 16) | (data[i + 1] << 8) | data[i + 2];
      },
      mirror: true,
    );
    final out = await _worker!.run(input);
    if (_onAngles == null) return;

    final angles = measureAngles(
      landmarksFromKeypoints(out.keypoints, mirrored: true),
    );
    if (angles.isNotEmpty) _onAngles?.call(angles);
    _form.value = _coach!.update(out.probabilities);
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
