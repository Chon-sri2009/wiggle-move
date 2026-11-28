/// Counts repetitions of one joint angle. Pure Dart (no camera/Flutter).
///
/// A rep is a full cycle: the angle reaches [low] (e.g. knee bent in a squat,
/// arms down in a jumping jack) and then returns up to [high]. Two thresholds
/// (hysteresis) keep sensor jitter around a single value from counting twice.
class RepCounter {
  RepCounter({required this.low, required this.high})
    : assert(low < high, 'low must be below high');

  final double low;
  final double high;
  int _count = 0;
  bool _reachedLow = false;

  int get count => _count;

  /// Feeds one measured angle (degrees).
  void update(double angle) {
    if (!_reachedLow) {
      if (angle <= low) _reachedLow = true;
    } else if (angle >= high) {
      _reachedLow = false;
      _count++;
    }
  }
}
