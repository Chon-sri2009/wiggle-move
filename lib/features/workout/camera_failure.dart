// What the user is told when the workout cannot get a camera. Pure Dart so the
// wording and the Retry rule are unit-tested without a device.

enum CameraProblem {
  /// Permission refused (Android also reports a permanent refusal this way).
  denied,

  /// iOS: refused before, so the system will not ask again.
  deniedForever,

  /// Blocked by parental controls / device policy; nothing the user can retry.
  restricted,

  /// Pose detection is not available on this platform.
  unsupported,

  /// The device reports no camera at all.
  noCamera,

  other,
}

class CameraFailure {
  const CameraFailure(this.problem, this.message, {required this.canRetry});
  final CameraProblem problem;

  /// Safe to show to the user as is.
  final String message;

  /// Whether trying again can succeed (a new permission prompt, a busy
  /// camera). False when only a Settings change or another device helps.
  final bool canRetry;
}

const unsupportedPlatformFailure = CameraFailure(
  CameraProblem.unsupported,
  'Pose detection runs on Android and iOS only. Open the app on a phone.',
  canRetry: false,
);

const noCameraFailure = CameraFailure(
  CameraProblem.noCamera,
  'No camera was found on this device.',
  canRetry: false,
);

/// Maps a `CameraException.code` (from the camera plugin) to what to show.
CameraFailure cameraFailureFor(String code, [String? description]) {
  switch (code) {
    case 'CameraAccessDeniedWithoutPrompt':
      return const CameraFailure(
        CameraProblem.deniedForever,
        'Camera access is turned off for Wiggle Move. Open Settings > '
        'Wiggle Move and allow the camera, then come back.',
        canRetry: true,
      );
    case 'CameraAccessDenied':
    case 'cameraPermission':
      return const CameraFailure(
        CameraProblem.denied,
        'Wiggle Move needs the camera to check your moves. Allow it when '
        'asked, or turn it on in your phone Settings > Apps > Wiggle Move > '
        'Permissions.',
        canRetry: true,
      );
    case 'CameraAccessRestricted':
      return const CameraFailure(
        CameraProblem.restricted,
        'Camera access is restricted on this device, so moves cannot be '
        'checked.',
        canRetry: false,
      );
    default:
      final detail = description == null || description.isEmpty
          ? code
          : description;
      return CameraFailure(
        CameraProblem.other,
        'Camera problem: $detail',
        canRetry: true,
      );
  }
}
