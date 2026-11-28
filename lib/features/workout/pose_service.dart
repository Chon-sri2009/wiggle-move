import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../../shared/pose/pose_math.dart';

/// True where a pose source exists: ML Kit on Android/iOS, the pure-Dart
/// model engine on Windows (`DesktopCamera`).
bool get poseDetectionSupported =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.windows);

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
const _minLikelihood = 0.4;

/// Extracts a packed NV21 byte buffer from an Android [CameraImage], handling
/// both single-plane NV21 and 3-plane YUV_420_888 (delivered by many CameraX
/// devices even when NV21 is requested).
Uint8List? androidNv21Bytes(CameraImage image) {
  if (image.planes.length == 1) return image.planes.first.bytes;
  if (image.planes.length < 3) return null;
  final width = image.width;
  final height = image.height;
  final yPlane = image.planes[0];
  final uPlane = image.planes[1];
  final vPlane = image.planes[2];
  final out = Uint8List(width * height + (width * height) ~/ 2);
  var dst = 0;
  final yBytes = yPlane.bytes;
  final yStride = yPlane.bytesPerRow;
  for (var r = 0; r < height; r++) {
    final rowStart = r * yStride;
    for (var c = 0; c < width; c++) {
      out[dst++] = yBytes[rowStart + c];
    }
  }
  final uBytes = uPlane.bytes;
  final vBytes = vPlane.bytes;
  final uvStride = uPlane.bytesPerRow;
  final uvPixelStride = uPlane.bytesPerPixel ?? 1;
  final halfH = height ~/ 2;
  final halfW = width ~/ 2;
  for (var r = 0; r < halfH; r++) {
    final rowStart = r * uvStride;
    for (var c = 0; c < halfW; c++) {
      final idx = rowStart + c * uvPixelStride;
      out[dst++] = vBytes[idx];
      out[dst++] = uBytes[idx];
    }
  }
  return out;
}

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

    if (defaultTargetPlatform == TargetPlatform.android) {
      final bytes = androidNv21Bytes(image);
      if (bytes == null) return null;
      final bytesPerRow = image.planes.length == 1
          ? image.planes.first.bytesPerRow
          : image.width;
      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: bytesPerRow,
        ),
      );
    }

    if (format != InputImageFormat.bgra8888 || image.planes.length != 1) {
      return null;
    }

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
