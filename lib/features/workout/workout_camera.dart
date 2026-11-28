import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/env.dart';
import '../../shared/pose/angle_smoother.dart';
import '../../shared/pose/pose_math.dart';
import 'form/form_classifier.dart';
import 'form/form_coach.dart';
import 'form/form_feedback.dart';
import 'form/frame_preprocess.dart';
import 'desktop_camera.dart';
import 'pose_service.dart';

/// The device has no camera at all.
class NoCameraException implements Exception {
  const NoCameraException();
}

/// What the workout needs from a camera: open it, show a preview, and report
/// joint angles for each frame while streaming. The real implementation is
/// [MlKitCamera]; tests supply a fake, so the screen is testable without a
/// device.
abstract class WorkoutCamera {
  /// Opens the camera. Throws [CameraException] (permission, busy camera) or
  /// [NoCameraException].
  Future<void> open();

  bool get isOpen;

  Widget buildPreview();

  /// Width / height of the picture as [buildPreview] shows it (portrait on
  /// phones, landscape on Windows), so a small preview can keep its shape.
  double get previewAspect;

  /// Starts reporting the angles measured in each frame (frames where no pose
  /// was found are skipped).
  Future<void> startFrames(void Function(Map<Joint, double> angles) onAngles);

  Future<void> stopFrames();

  /// Live form feedback (null until the form coach has a verdict, and always
  /// null when it is switched off).
  ValueListenable<FormFeedback?> get formFeedback;

  Future<void> close();
}

typedef WorkoutCameraFactory = WorkoutCamera Function();

/// Makes one camera per workout attempt (Try again makes a new one).
final workoutCameraFactoryProvider = Provider<WorkoutCameraFactory>(
  (_) => defaultTargetPlatform == TargetPlatform.windows
      ? DesktopCamera.new
      : MlKitCamera.new,
);

/// Front camera + ML Kit pose detection.
class MlKitCamera implements WorkoutCamera {
  CameraController? _controller;
  PoseService? _pose;
  void Function(Map<Joint, double>)? _onAngles;
  bool _detecting = false;

  FormClassifier? _classifier;
  FormCoach? _coach;
  final _form = ValueNotifier<FormFeedback?>(null);
  final _smoother = AngleSmoother(alpha: 0.65, maxJumpDeg: 120.0);
  final _formInput = Float32List(modelInputSize * modelInputSize * 3);
  final _formClock = Stopwatch()..start();
  int _lastFormMs = -formIntervalMs;

  /// The form model is heavy (a second CNN per frame), so it looks at a few
  /// frames per second only.
  static const formIntervalMs = 400;

  @override
  ValueListenable<FormFeedback?> get formFeedback => _form;

  @override
  bool get isOpen => _controller?.value.isInitialized ?? false;

  @override
  Future<void> open() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) throw const NoCameraException();
    final description = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    final controller = CameraController(
      description,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: poseImageFormat,
    );
    _controller = controller;
    await controller.initialize();
    _pose = PoseService();
    if (Env.formCoach) {
      try {
        final classifier = await TfliteFormClassifier.load();
        _classifier = classifier;
        _coach = FormCoach(classifier.labels);
      } catch (_) {
        _coach = null; // the workout still works without form feedback
      }
    }
  }

  @override
  double get previewAspect {
    final size = _controller?.value.previewSize;
    return size == null ? 3 / 4 : size.height / size.width;
  }

  @override
  Widget buildPreview() {
    final controller = _controller!;
    final size = controller.value.previewSize!;
    // Preview size is reported in landscape; the app is portrait-locked.
    return ExcludeSemantics(
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: size.height,
            height: size.width,
            child: CameraPreview(controller),
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
    _smoother.reset();
    await _controller!.startImageStream(_onImage);
  }

  Future<void> _onImage(CameraImage image) async {
    if (_detecting || _onAngles == null) return;
    _detecting = true;
    try {
      final angles = await _pose!.detect(image, _controller!.description);
      if (angles != null && angles.isNotEmpty) {
        final smoothed = _smoother.add(angles);
        if (smoothed.isNotEmpty) _onAngles?.call(smoothed);
      }
      _coachFrame(image);
    } finally {
      _detecting = false;
    }
  }

  void _coachFrame(CameraImage image) {
    final coach = _coach;
    if (coach == null || _onAngles == null) return;
    final now = _formClock.elapsedMilliseconds;
    if (now - _lastFormMs < formIntervalMs) return;
    _lastFormMs = now;
    try {
      final description = _controller!.description;
      final android = defaultTargetPlatform == TargetPlatform.android;
      final PixelAt pixelAt;
      if (android) {
        final nv21 = androidNv21Bytes(image);
        if (nv21 == null) return;
        final stride = image.planes.length == 1
            ? image.planes.first.bytesPerRow
            : image.width;
        pixelAt = nv21Pixels(nv21, image.width, image.height, stride);
      } else {
        final plane = image.planes.first;
        pixelAt = bgraPixels(plane.bytes, plane.bytesPerRow);
      }
      final input = preprocessFrame(
        width: image.width,
        height: image.height,
        pixelAt: pixelAt,
        rotationDegrees: description.sensorOrientation,
        // The model learned from mirrored webcam images.
        mirror: description.lensDirection == CameraLensDirection.front,
        out: _formInput,
      );
      _form.value = coach.update(_classifier!.classify(input));
    } catch (_) {
      // A bad frame must never end the workout.
    }
  }

  @override
  Future<void> stopFrames() async {
    _onAngles = null;
    final controller = _controller;
    if (controller != null && controller.value.isStreamingImages) {
      await controller.stopImageStream();
    }
  }

  @override
  Future<void> close() async {
    _onAngles = null;
    _classifier?.close();
    _form.dispose();
    await _controller?.dispose();
    await _pose?.close();
  }
}
