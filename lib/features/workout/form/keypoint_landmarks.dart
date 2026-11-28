import '../../../shared/pose/pose_math.dart';
import 'posenet_engine.dart';

/// Keypoints below this score are treated as not visible (ML Kit's own cut-off
/// is 0.5, and PoseNet points below 0.4 are often background noise).
const keypointMinScore = 0.4;

const _lm = <PosePart, Lm>{
  PosePart.leftShoulder: Lm.leftShoulder,
  PosePart.rightShoulder: Lm.rightShoulder,
  PosePart.leftElbow: Lm.leftElbow,
  PosePart.rightElbow: Lm.rightElbow,
  PosePart.leftWrist: Lm.leftWrist,
  PosePart.rightWrist: Lm.rightWrist,
  PosePart.leftHip: Lm.leftHip,
  PosePart.rightHip: Lm.rightHip,
  PosePart.leftKnee: Lm.leftKnee,
  PosePart.rightKnee: Lm.rightKnee,
  PosePart.leftAnkle: Lm.leftAnkle,
  PosePart.rightAnkle: Lm.rightAnkle,
};

Lm _opposite(Lm lm) => switch (lm) {
  Lm.leftShoulder => Lm.rightShoulder,
  Lm.rightShoulder => Lm.leftShoulder,
  Lm.leftElbow => Lm.rightElbow,
  Lm.rightElbow => Lm.leftElbow,
  Lm.leftWrist => Lm.rightWrist,
  Lm.rightWrist => Lm.leftWrist,
  Lm.leftHip => Lm.rightHip,
  Lm.rightHip => Lm.leftHip,
  Lm.leftKnee => Lm.rightKnee,
  Lm.rightKnee => Lm.leftKnee,
  Lm.leftAnkle => Lm.rightAnkle,
  Lm.rightAnkle => Lm.leftAnkle,
};

/// The app's landmarks from decoded keypoints. PoseNet names sides by what it
/// sees; on a mirrored image (which is what the model is fed) the person's
/// real right arm looks like a left arm, so [mirrored] swaps the sides back.
/// Angles do not depend on the 257 px scale, so no unscaling is needed.
Map<Lm, Pt> landmarksFromKeypoints(
  List<PoseKeypoint> keypoints, {
  required bool mirrored,
  double minScore = keypointMinScore,
}) {
  final points = <Lm, Pt>{};
  for (final entry in _lm.entries) {
    final k = keypoints[entry.key.index];
    if (k.score < minScore) continue;
    points[mirrored ? _opposite(entry.value) : entry.value] = Pt(k.x, k.y);
  }
  return points;
}
