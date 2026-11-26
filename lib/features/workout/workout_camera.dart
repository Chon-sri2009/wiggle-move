import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/pose/pose_math.dart';
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

  /// Starts reporting the angles measured in each frame (frames where no pose
  /// was found are skipped).
  Future<void> startFrames(void Function(Map<Joint, double> angles) onAngles);

  Future<void> stopFrames();

  Future<void> close();
}

typedef WorkoutCameraFactory = WorkoutCamera Function();

/// Makes one camera per workout attempt (Try again makes a new one).
final workoutCameraFactoryProvider = Provider<WorkoutCameraFactory>(
  (_) => MlKitCamera.new,
);

/// Front camera + ML Kit pose detection.
class MlKitCamera implements WorkoutCamera {
  CameraController? _controller;
  PoseService? _pose;
  void Function(Map<Joint, double>)? _onAngles;
  bool _detecting = false;

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
    await _controller!.startImageStream(_onImage);
  }

  Future<void> _onImage(CameraImage image) async {
    if (_detecting || _onAngles == null) return;
    _detecting = true;
    try {
      final angles = await _pose!.detect(image, _controller!.description);
      if (angles != null) _onAngles?.call(angles);
    } finally {
      _detecting = false;
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
    await _controller?.dispose();
    await _pose?.close();
  }
}
