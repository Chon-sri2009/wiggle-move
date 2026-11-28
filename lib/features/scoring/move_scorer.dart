import '../../shared/pose/pose_math.dart';

class MoveResult {
  const MoveResult({
    required this.score,
    required this.frames,
    this.worstJoint,
    this.worstSignedDeviation,
    this.reps = 0,
  });

  /// 0–100.
  final int score;

  /// Reps counted (0 for timed poses). Summed over sets for a whole move.
  final int reps;

  /// Number of camera frames that contributed.
  final int frames;

  /// Joint furthest from target (null if all joints were within tolerance
  /// or the user was never visible).
  final Joint? worstJoint;

  /// measured − target, averaged over the move. Positive = angle too large.
  final double? worstSignedDeviation;

  bool get wasVisible => frames > 0;
}

/// Accumulates frames for one move and produces a [MoveResult].
class MoveScorer {
  MoveScorer(this.target);

  /// Deviation (degrees) with no penalty.
  static const toleranceDeg = 15.0;

  /// Further degrees beyond tolerance until a joint scores zero.
  static const falloffDeg = 45.0;

  final MoveTarget target;

  /// The joint furthest out of tolerance in the last judged frame (null if
  /// none), and by how much (measured - target).
  Joint? lastWorst;
  double lastWorstSigned = 0;
  final List<double> _frameScores = [];
  final Map<Joint, List<double>> _signedDeviations = {};

  /// Scores one frame (0–1) or returns null if too few target joints were
  /// visible to judge.
  ///
  /// [against] replaces the move's own target for this frame (a trainer video
  /// gives a different target at every moment).
  double? addFrame(Map<Joint, double> measured, {MoveTarget? against}) {
    final goal = against ?? target;
    final visible = goal.angles.keys.where(measured.containsKey).toList();
    if (visible.length * 2 < goal.angles.length || visible.isEmpty) {
      return null;
    }

    var sum = 0.0;
    lastWorst = null;
    lastWorstSigned = 0;
    for (final joint in visible) {
      final signed = measured[joint]! - goal.angles[joint]!;
      _signedDeviations.putIfAbsent(joint, () => []).add(signed);
      sum += _jointScore(signed.abs());
      if (signed.abs() > toleranceDeg && signed.abs() > lastWorstSigned.abs()) {
        lastWorst = joint;
        lastWorstSigned = signed;
      }
    }
    final frameScore = sum / visible.length;
    _frameScores.add(frameScore);
    return frameScore;
  }

  /// Timing slack: the move is judged on the best half of its frames, so a
  /// user who reaches the pose late or leaves early is not punished for it.
  MoveResult finish() {
    if (_frameScores.isEmpty) return const MoveResult(score: 0, frames: 0);

    final sorted = [..._frameScores]..sort((a, b) => b.compareTo(a));
    final top = sorted.take((sorted.length + 1) ~/ 2);
    final score = (top.reduce((a, b) => a + b) / top.length * 100).round();

    Joint? worst;
    var worstSigned = 0.0;
    for (final entry in _signedDeviations.entries) {
      final mean = entry.value.reduce((a, b) => a + b) / entry.value.length;
      if (mean.abs() > toleranceDeg && mean.abs() > worstSigned.abs()) {
        worst = entry.key;
        worstSigned = mean;
      }
    }
    return MoveResult(
      score: score,
      frames: _frameScores.length,
      worstJoint: worst,
      worstSignedDeviation: worst == null ? null : worstSigned,
    );
  }

  static double _jointScore(double deviation) {
    if (deviation <= toleranceDeg) return 1;
    return (1 - (deviation - toleranceDeg) / falloffDeg).clamp(0.0, 1.0);
  }
}
