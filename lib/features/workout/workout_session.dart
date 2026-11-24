import '../scoring/move_scorer.dart';
import '../scoring/pose_math.dart';
import '../trainers/trainer.dart';

class MoveOutcome {
  const MoveOutcome(this.move, this.result);
  final Move move;
  final MoveResult result;
}

class SessionSummary {
  const SessionSummary({required this.routine, required this.outcomes});
  final Routine routine;
  final List<MoveOutcome> outcomes;

  int get totalScore => outcomes.isEmpty
      ? 0
      : (outcomes.map((o) => o.result.score).reduce((a, b) => a + b) /
                outcomes.length)
            .round();
}

/// Tracks which move is active for a routine and scores frames against it.
/// Pure Dart: the screen feeds it elapsed time and measured angles.
class WorkoutSession {
  WorkoutSession(this.routine)
    : _scorer = MoveScorer(routine.moves.first.target);

  final Routine routine;
  final List<MoveOutcome> _outcomes = [];
  MoveScorer _scorer;
  int _index = 0;

  int get moveIndex => _index.clamp(0, routine.moves.length - 1);
  Move get currentMove => routine.moves[moveIndex];
  bool get isDone => _index >= routine.moves.length;

  /// Moves to the move active at [elapsedMs], finalizing any moves passed.
  void advance(int elapsedMs) {
    var boundary = 0;
    var target = 0;
    for (final move in routine.moves) {
      boundary += move.durationMs;
      if (elapsedMs >= boundary) target++;
    }
    while (_index < target) {
      _outcomes.add(MoveOutcome(routine.moves[_index], _scorer.finish()));
      _index++;
      if (_index < routine.moves.length) {
        _scorer = MoveScorer(routine.moves[_index].target);
      }
    }
  }

  /// Scores a camera frame against the current move. Returns 0–1, or null if
  /// the frame couldn't be judged.
  double? addFrame(Map<Joint, double> angles) =>
      isDone ? null : _scorer.addFrame(angles);

  SessionSummary summary() {
    assert(isDone, 'summary() before the routine finished');
    return SessionSummary(
      routine: routine,
      outcomes: List.unmodifiable(_outcomes),
    );
  }
}
