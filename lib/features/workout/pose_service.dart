import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../scoring/pose_math.dart';

/// True where ML Kit pose detection exists.
bool get poseDetectionSupported =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Camera format ML Kit expects on this platform.
ImageFormatGroup get poseImageFormat =>
    defaultTargetPlatform == TargetPlatform.android
    ? ImageFormatGroup.nv21
    : ImageFormatGroup.bgra8888;

const _landmarkMap = <PoseLandmarkType, Lm>{
  PoseLandmarkType.leftShoulder: Lm.leftShoulder,
  PoseLandmarkType.rightShoulder: Lm.rightShoulder,
  PoseLandmarkType.leftElbow: Lm.leftElbow,
  PoseLandmarkType.rightElbow: Lm.rightElbow,
  PoseLandmarkType.leftWrist: Lm.leftWrist,
  PoseLandmarkType.rightWrist: Lm.rightWrist,
  PoseLandmarkType.leftHip: Lm.leftHip,
  PoseLandmarkType.rightHip: Lm.rightHip,
  PoseLandmarkType.leftKnee: Lm.leftKnee,
  PoseLandmarkType.rightKnee: Lm.rightKnee,
  PoseLandmarkType.leftAnkle: Lm.leftAnkle,
  PoseLandmarkType.rightAnkle: Lm.rightAnkle,
};

/// Landmarks below this confidence are treated as not visible.
const _minLikelihood = 0.5;

/// Wraps ML Kit: camera frame in, joint angles out.
/// The app is locked to portrait, so image rotation equals sensor orientation.
class PoseService {
  final _detector = PoseDetector(
    options: PoseDetectorOptions(mode: PoseDetectionMode.stream),
  );

  Future<Map<Joint, double>?> detect(
    CameraImage image,
    CameraDescription camera,
  ) async {
    final input = _toInputImage(image, camera);
    if (input == null) return null;

    final poses = await _detector.processImage(input);
    if (poses.isEmpty) return null;

    final points = <Lm, Pt>{};
    for (final entry in poses.first.landmarks.entries) {
      final lm = _landmarkMap[entry.key];
      if (lm != null && entry.value.likelihood >= _minLikelihood) {
        points[lm] = Pt(entry.value.x, entry.value.y);
      }
    }
    return measureAngles(points);
  }

  InputImage? _toInputImage(CameraImage image, CameraDescription camera) {
    final rotation = InputImageRotationValue.fromRawValue(
      camera.sensorOrientation,
    );
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (rotation == null || format == null) return null;

    final expected = defaultTargetPlatform == TargetPlatform.android
        ? InputImageFormat.nv21
        : InputImageFormat.bgra8888;
    if (format != expected || image.planes.length != 1) return null;

    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  Future<void> close() => _detector.close();
}
