import 'dart:math' show min;

import '../scoring/move_scorer.dart';
import '../../shared/pose/pose_math.dart';
import '../../shared/pose/rep_counter.dart';
import '../../shared/backend/content_models.dart';
import '../../shared/backend/sessions_repository.dart';
import '../../shared/calories.dart';

/// A set's counted reps are capped at this multiple of the move's reps
/// target. Reps over the target add no score, and the server rejects a play
/// (permanently) whose reps exceed target x sets x its REPS_OVERSHOOT
/// (supabase/functions/submit_session/validate.ts): keep the two equal.
const maxRepsOvershoot = 3;

/// One move across all its sets: [result] is the aggregate (mean score,
/// summed reps and frames, the worst joint of the worst set).
class MoveOutcome {
  const MoveOutcome(this.move, this.result);
  final Move move;
  final MoveResult result;
}

class SessionSummary {
  const SessionSummary({
    required this.routine,
    required this.outcomes,
    this.durationMs,
  });
  final Routine routine;
  final List<MoveOutcome> outcomes;

  /// Measured play time, null when unknown (e.g. built for a test).
  final int? durationMs;

  int get totalScore => outcomes.isEmpty
      ? 0
      : (outcomes.map((o) => o.result.score).reduce((a, b) => a + b) /
                outcomes.length)
            .round();

  int get totalReps => outcomes.fold(0, (sum, o) => sum + o.result.reps);

  /// Reps asked for over all sets (counted moves only).
  int get targetReps => outcomes.fold(
    0,
    (sum, o) => sum + (o.move.rep?.target ?? 0) * routine.sets,
  );

  /// Estimated kcal, or null when the duration is unknown.
  int? get calories => durationMs == null
      ? null
      : estimateCalories(met: routine.met, durationMs: durationMs!);

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
    sets: routine.sets,
    playedAt: playedAt,
    userId: userId,
    results: [
      for (var i = 0; i < outcomes.length; i++)
        MoveSubmission(
          moveIdx: i,
          score: outcomes[i].result.score,
          reps: outcomes[i].result.reps,
          worstJoint: outcomes[i].result.worstJoint?.name,
          deviation: outcomes[i].result.worstSignedDeviation,
        ),
    ],
  );
}

/// A stretch of the timeline: one move of one set, or a rest ([move] null).
class _Segment {
  const _Segment(this.set, this.move, this.endMs);
  final int set;
  final int? move;
  final int endMs;
}

/// Tracks the active move/set/rest for a routine and scores frames against
/// it. Pure Dart: the screen feeds it elapsed time and measured angles.
///
/// The routine's moves are played `routine.sets` times with `routine.restMs`
/// between sets. A counted move ([Move.rep]) gets its form score scaled by
/// min(1, reps / target) for that set, so skipping reps costs points. Frames
/// during a rest are ignored.
class WorkoutSession {
  WorkoutSession(this.routine)
    : _results = [for (final _ in routine.moves) <MoveResult>[]] {
    var t = 0;
    for (var s = 0; s < routine.sets; s++) {
      for (var i = 0; i < routine.moves.length; i++) {
        t += routine.moves[i].durationMs;
        _segments.add(_Segment(s, i, t));
      }
      if (s < routine.sets - 1 && routine.restMs > 0) {
        t += routine.restMs;
        _segments.add(_Segment(s, null, t));
      }
    }
    _begin();
  }

  final Routine routine;
  final List<_Segment> _segments = [];
  final List<List<MoveResult>> _results; // per move, one entry per set
  int _index = 0;
  int _elapsedMs = 0;
  MoveScorer? _scorer;
  RepCounter? _counter;

  bool get isDone => _index >= _segments.length;
  bool get isResting => !isDone && _segments[_index].move == null;

  /// 0-based set being played (or just finished, during a rest).
  int get setIndex => isDone ? routine.sets - 1 : _segments[_index].set;

  /// The active move; during a rest, the move that comes next.
  int get moveIndex {
    if (isDone) return routine.moves.length - 1;
    return _segments[_index].move ?? _segments[_index + 1].move!;
  }

  Move get currentMove => routine.moves[moveIndex];

  /// Reps counted so far in the current set of the current move.
  int get repCount => _counter?.count ?? 0;

  /// Milliseconds left of the current rest (0 when not resting).
  int get restRemainingMs =>
      isResting ? (_segments[_index].endMs - _elapsedMs).clamp(0, 1 << 30) : 0;

  void _begin() {
    _scorer = null;
    _counter = null;
    if (isDone) return;
    final m = _segments[_index].move;
    if (m == null) return;
    final move = routine.moves[m];
    _scorer = MoveScorer(move.target);
    final rep = move.rep;
    if (rep != null) _counter = RepCounter(low: rep.low, high: rep.high);
  }

  void _finishSegment() {
    final seg = _segments[_index];
    final m = seg.move;
    if (m != null) {
      var result = _scorer!.finish();
      final rep = routine.moves[m].rep;
      if (rep != null) {
        final reps = min(_counter!.count, rep.target * maxRepsOvershoot);
        final factor = reps >= rep.target ? 1.0 : reps / rep.target;
        result = MoveResult(
          score: (result.score * factor).round(),
          frames: result.frames,
          worstJoint: result.worstJoint,
          worstSignedDeviation: result.worstSignedDeviation,
          reps: reps,
        );
      }
      _results[m].add(result);
    }
    _index++;
    _begin();
  }

  /// Moves to the segment active at [elapsedMs], finalizing any passed.
  void advance(int elapsedMs) {
    _elapsedMs = elapsedMs;
    while (!isDone && elapsedMs >= _segments[_index].endMs) {
      _finishSegment();
    }
  }

  /// Scores a camera frame against the current move. Returns 0–1, or null if
  /// the frame couldn't be judged (resting, done, or too few joints seen).
  double? addFrame(Map<Joint, double> angles) {
    final scorer = _scorer;
    if (scorer == null) return null;
    final rep = routine.moves[_segments[_index].move!].rep;
    if (rep != null) {
      final angle = angles[rep.joint];
      if (angle != null) _counter!.update(angle);
    }
    return scorer.addFrame(angles);
  }

  SessionSummary summary({int? durationMs}) {
    assert(isDone, 'summary() before the routine finished');
    return SessionSummary(
      routine: routine,
      durationMs: durationMs,
      outcomes: [
        for (var i = 0; i < routine.moves.length; i++)
          MoveOutcome(routine.moves[i], _aggregate(_results[i])),
      ],
    );
  }

  static MoveResult _aggregate(List<MoveResult> sets) {
    if (sets.length == 1) return sets.first;
    final score = (sets.fold(0, (sum, r) => sum + r.score) / sets.length)
        .round();
    MoveResult? worst;
    for (final r in sets) {
      final d = r.worstSignedDeviation;
      if (d == null) continue;
      final w = worst?.worstSignedDeviation;
      if (w == null || d.abs() > w.abs()) worst = r;
    }
    return MoveResult(
      score: score,
      frames: sets.fold(0, (sum, r) => sum + r.frames),
      reps: sets.fold(0, (sum, r) => sum + r.reps),
      worstJoint: worst?.worstJoint,
      worstSignedDeviation: worst?.worstSignedDeviation,
    );
  }
}
