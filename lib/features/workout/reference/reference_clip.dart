import 'dart:math' as math;

import '../../../shared/pose/pose_math.dart';
import '../form/keypoint_landmarks.dart';
import '../form/posenet_engine.dart';

/// A trainer's moves over time: the joint angles at each sample of a video,
/// made once by `tool/pose_model/video_to_timeline.py`. The workout compares
/// the user's angles with the ones the trainer has at the same moment.
class ReferenceClip {
  ReferenceClip._(this.sampleMs, this.durationMs, this._angles);

  /// [json] is the tool's output. [mirrored] swaps left and right: a trainer
  /// who faces the camera is copied as in a mirror, so the user's right arm
  /// follows the trainer's left. When [joints] is given, only those joints are
  /// judged (e.g. hips and knees for a squat video, ignoring noisy arm motion).
  factory ReferenceClip.fromJson(
    Object? json, {
    bool mirrored = true,
    Set<Joint>? joints,
  }) {
    final map = json as Map<String, dynamic>;
    final samples = (map['samples'] as List<dynamic>).cast<List<dynamic>>();
    final hz = (map['hz'] as num).toDouble();
    return ReferenceClip._(1000 / hz, (map['durationMs'] as num).toInt(), [
      for (final row in samples)
        () {
          final all = measureAngles(
            landmarksFromKeypoints([
              for (var k = 0; k < 17; k++)
                PoseKeypoint(
                  (row[3 * k] as num).toDouble(),
                  (row[3 * k + 1] as num).toDouble(),
                  (row[3 * k + 2] as num).toDouble(),
                ),
            ], mirrored: mirrored),
          );
          if (joints == null) return all;
          return {
            for (final e in all.entries)
              if (joints.contains(e.key)) e.key: e.value,
          };
        }(),
    ]);
  }

  final double sampleMs;
  final int durationMs;
  final List<Map<Joint, double>> _angles;

  /// People react slightly after (or anticipate slightly ahead of) the trainer
  /// on screen; allow generous timing slack so following the video feels fair.
  static const lagMs = 1500;
  static const leadMs = 500;

  /// The trainer's angles to judge [measured] against at [offsetMs] into the
  /// clip: of the samples within the lag/lead window, the one the user is
  /// closest to (so being a beat late is not punished). Null when the clip has
  /// no usable sample there.
  Map<Joint, double>? targetAt(int offsetMs, Map<Joint, double> measured) {
    if (_angles.isEmpty) return null;
    final last = _angles.length - 1;
    int index(num ms) => (ms / sampleMs).round().clamp(0, last);
    final from = index(offsetMs - lagMs), to = index(offsetMs + leadMs);
    Map<Joint, double>? best;
    var bestDeviation = double.infinity;
    for (var i = from; i <= to; i++) {
      final candidate = _angles[i];
      var sum = 0.0, n = 0;
      for (final e in candidate.entries) {
        final m = measured[e.key];
        if (m == null) continue;
        sum += (m - e.value).abs();
        n++;
      }
      if (n < 2) continue;
      final mean = sum / n;
      if (mean < bestDeviation) {
        bestDeviation = mean;
        best = candidate;
      }
    }
    if (best != null) return best;
    final now = _angles[index(offsetMs)];
    return now.length >= 2 ? now : null;
  }

  int get sampleCount => _angles.length;
  double get seconds => math.max(durationMs, 0) / 1000;
}
