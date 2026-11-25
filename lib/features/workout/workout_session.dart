import '../scoring/move_scorer.dart';
import '../../shared/pose/pose_math.dart';
import '../../shared/backend/content_models.dart';
import '../../shared/backend/sessions_repository.dart';

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

  /// The `submit_session` payload for this play. [score] is [totalScore]
  /// (the server checks it against round(mean of move scores) ±1); move
  /// indexes are positions in the routine. [clientNonce] must be generated
  /// once per play so retries stay idempotent.
  SessionSubmission toSubmission({
    required String userId,
    required String clientNonce,
    required int durationMs,
    required DateTime playedAt,
  }) => SessionSubmission(
    routineId: routine.id,
    clientNonce: clientNonce,
    durationMs: durationMs,
    score: totalScore,
    playedAt: playedAt,
    userId: userId,
    results: [
      for (var i = 0; i < outcomes.length; i++)
        MoveSubmission(
          moveIdx: i,
          score: outcomes[i].result.score,
          worstJoint: outcomes[i].result.worstJoint?.name,
          deviation: outcomes[i].result.worstSignedDeviation,
        ),
    ],
  );
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
