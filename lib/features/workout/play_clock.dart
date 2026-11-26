/// Play time that excludes pauses. The workout timeline and the submitted
/// `duration_ms` both come from here, so a play that was backgrounded or
/// paused is not stretched (the server rejects durations over 3x the routine).
class PlayClock {
  PlayClock(this._nowMs);

  final int Function() _nowMs;
  int _accumulatedMs = 0;
  int? _startedAt;

  bool get isRunning => _startedAt != null;

  int get elapsedMs {
    final started = _startedAt;
    return _accumulatedMs + (started == null ? 0 : _nowMs() - started);
  }

  /// Starts, or resumes after [pause]. No-op while already running.
  void start() => _startedAt ??= _nowMs();

  /// Stops counting, keeping the time so far. No-op while stopped.
  void pause() {
    final started = _startedAt;
    if (started == null) return;
    _accumulatedMs += _nowMs() - started;
    _startedAt = null;
  }
}
