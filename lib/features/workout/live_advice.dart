import '../../shared/pose/pose_math.dart';

/// Turns the worst joint of each frame into one steady message: a joint must be
/// off for [framesToShow] frames in a row before a warning appears, and the
/// user must be fine for [framesToClear] frames before it goes, so the text
/// does not flicker.
class LiveAdvice {
  static const framesToShow = 3;
  static const framesToClear = 2;

  Joint? _candidate;
  bool _candidateOpen = false;
  int _off = 0;
  int _good = 0;
  String? _shown;

  String? get message => _shown;

  /// [worst] is the joint furthest out of tolerance this frame (null if all
  /// are fine); [signed] is measured - target (positive = angle too large).
  String? add(Joint? worst, double signed) {
    if (worst == null) {
      _candidate = null;
      _off = 0;
      if (++_good >= framesToClear) _shown = null;
      return _shown;
    }
    _good = 0;
    final open = signed > 0;
    if (worst == _candidate && open == _candidateOpen) {
      _off++;
    } else {
      _candidate = worst;
      _candidateOpen = open;
      _off = 1;
    }
    if (_off >= framesToShow) {
      final hint = worst.hint(open);
      _shown = hint[0].toUpperCase() + hint.substring(1);
    }
    return _shown;
  }

  void reset() {
    _candidate = null;
    _off = 0;
    _good = 0;
    _shown = null;
  }
}
