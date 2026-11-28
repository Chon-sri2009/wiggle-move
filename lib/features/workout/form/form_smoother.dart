/// Steadies the per-frame model output: a label only becomes the stable one
/// after [framesToSwitch] confident frames in a row, so a single noisy frame
/// never flips the feedback on screen.
class FormSmoother {
  FormSmoother({this.minConfidence = 0.7, this.framesToSwitch = 2});

  final double minConfidence;
  final int framesToSwitch;

  String? _stable;
  String? _candidate;
  int _count = 0;

  /// The label the user should currently see feedback for (null until the
  /// first one is established).
  String? get stable => _stable;

  /// Feeds one frame's best label and its probability; returns [stable].
  String? add(String label, double confidence) {
    if (confidence < minConfidence) {
      // An unsure frame breaks any pending switch so stale noisy frames cannot
      // accumulate across uncertain gaps.
      _candidate = null;
      _count = 0;
      return _stable;
    }
    if (label == _stable) {
      _candidate = null;
      _count = 0;
    } else if (label == _candidate) {
      if (++_count >= framesToSwitch) {
        _stable = label;
        _candidate = null;
        _count = 0;
      }
    } else {
      _candidate = label;
      _count = 1;
      if (framesToSwitch <= 1) {
        _stable = label;
        _candidate = null;
        _count = 0;
      }
    }
    return _stable;
  }

  void reset() {
    _stable = null;
    _candidate = null;
    _count = 0;
  }
}
