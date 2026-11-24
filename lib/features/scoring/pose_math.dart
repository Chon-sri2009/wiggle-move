import 'dart:math';

/// Body landmarks we use. Mapped from ML Kit in the pose service so this
/// file stays free of Flutter/plugin imports.
enum Lm {
  leftShoulder,
  rightShoulder,
  leftElbow,
  rightElbow,
  leftWrist,
  rightWrist,
  leftHip,
  rightHip,
  leftKnee,
  rightKnee,
  leftAnkle,
  rightAnkle,
}

class Pt {
  const Pt(this.x, this.y);
  final double x;
  final double y;
}

enum JointKind { elbow, shoulder, hip, knee }

/// A joint angle measured at [vertex] between the segments to [a] and [c].
enum Joint {
  leftElbow(
    Lm.leftShoulder,
    Lm.leftElbow,
    Lm.leftWrist,
    JointKind.elbow,
    'left elbow',
  ),
  rightElbow(
    Lm.rightShoulder,
    Lm.rightElbow,
    Lm.rightWrist,
    JointKind.elbow,
    'right elbow',
  ),
  leftShoulder(
    Lm.leftElbow,
    Lm.leftShoulder,
    Lm.leftHip,
    JointKind.shoulder,
    'left shoulder',
  ),
  rightShoulder(
    Lm.rightElbow,
    Lm.rightShoulder,
    Lm.rightHip,
    JointKind.shoulder,
    'right shoulder',
  ),
  leftHip(Lm.leftShoulder, Lm.leftHip, Lm.leftKnee, JointKind.hip, 'left hip'),
  rightHip(
    Lm.rightShoulder,
    Lm.rightHip,
    Lm.rightKnee,
    JointKind.hip,
    'right hip',
  ),
  leftKnee(Lm.leftHip, Lm.leftKnee, Lm.leftAnkle, JointKind.knee, 'left knee'),
  rightKnee(
    Lm.rightHip,
    Lm.rightKnee,
    Lm.rightAnkle,
    JointKind.knee,
    'right knee',
  );

  const Joint(this.a, this.vertex, this.c, this.kind, this.label);
  final Lm a;
  final Lm vertex;
  final Lm c;
  final JointKind kind;
  final String label;

  /// Coaching hint. [tooOpen] means the user's angle was larger than the target.
  String hint(bool tooOpen) => switch (kind) {
    JointKind.elbow || JointKind.knee =>
      tooOpen ? 'bend your $label more' : 'straighten your $label',
    JointKind.shoulder =>
      tooOpen
          ? 'lower your ${label.split(' ').first} arm'
          : 'raise your ${label.split(' ').first} arm higher',
    JointKind.hip =>
      tooOpen
          ? 'bend more at the ${label.split(' ').first} hip'
          : 'stand more upright',
  };
}

/// Angle in degrees (0–180) at [b] between rays b→a and b→c.
/// Returns null if either segment has zero length.
double? angleDeg(Pt a, Pt b, Pt c) {
  final v1x = a.x - b.x, v1y = a.y - b.y;
  final v2x = c.x - b.x, v2y = c.y - b.y;
  if ((v1x == 0 && v1y == 0) || (v2x == 0 && v2y == 0)) return null;
  final dot = v1x * v2x + v1y * v2y;
  final cross = v1x * v2y - v1y * v2x;
  return atan2(cross.abs(), dot) * 180 / pi;
}

/// Angles for every joint whose three landmarks are present.
Map<Joint, double> measureAngles(Map<Lm, Pt> points) {
  final result = <Joint, double>{};
  for (final joint in Joint.values) {
    final a = points[joint.a], b = points[joint.vertex], c = points[joint.c];
    if (a == null || b == null || c == null) continue;
    final angle = angleDeg(a, b, c);
    if (angle != null) result[joint] = angle;
  }
  return result;
}
