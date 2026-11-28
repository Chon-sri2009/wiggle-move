import '../pose/pose_math.dart';

/// Smooths noisy per-frame joint angles with an exponential moving average and
/// damps single-frame keypoint glitches so scoring, rep counting, and live
/// coaching cues do not flicker or trigger on outlier frames.
class AngleSmoother {
  AngleSmoother({
    this.alpha = 0.55,
    this.maxJumpDeg = 120.0,
    this.maxMissingFrames = 3,
  });

  /// Smoothing factor in (0, 1]. Higher reacts faster; lower smooths more.
  final double alpha;

  /// Single-frame angle jump above which the frame is treated as a likely
  /// keypoint glitch and given reduced weight.
  final double maxJumpDeg;

  /// Consecutive frames a joint may be absent before its state is cleared.
  final int maxMissingFrames;

  final Map<Joint, double> _smoothed = {};
  final Map<Joint, int> _missing = {};

  /// Returns a smoothed copy of [measured] for the current frame.
  Map<Joint, double> add(Map<Joint, double> measured) {
    final out = <Joint, double>{};
    for (final joint in Joint.values) {
      final raw = measured[joint];
      if (raw == null) {
        final missed = (_missing[joint] ?? 0) + 1;
        if (missed > maxMissingFrames) {
          _smoothed.remove(joint);
          _missing.remove(joint);
        } else {
          _missing[joint] = missed;
        }
        continue;
      }
      _missing[joint] = 0;
      final prev = _smoothed[joint];
      if (prev == null) {
        _smoothed[joint] = raw;
      } else {
        final diff = raw - prev;
        final k = diff.abs() > maxJumpDeg ? alpha * 0.25 : alpha;
        _smoothed[joint] = prev + k * diff;
      }
      out[joint] = _smoothed[joint]!;
    }
    return out;
  }

  void reset() {
    _smoothed.clear();
    _missing.clear();
  }
}
