import 'package:flutter_test/flutter_test.dart';
import 'package:wiggle_move/shared/pose/pose_math.dart';
import 'package:wiggle_move/shared/backend/trainer_data.dart';
import 'package:wiggle_move/features/workout/workout_session.dart';

void main() {
  final routine = builtInTrainers.first.routines.first;
  submissionTests();

  test('advances through moves by elapsed time and finishes', () {
    final s = WorkoutSession(routine);
    expect(s.currentMove, routine.moves.first);
    s.advance(routine.moves.first.durationMs + 1);
    expect(s.moveIndex, 1);
    s.advance(routine.durationMs);
    expect(s.isDone, isTrue);
    expect(s.summary().outcomes.length, routine.moves.length);
  });

  test('frames score against the current move; perfect pose gives 100', () {
    final s = WorkoutSession(routine);
    final target = routine.moves.first.target.angles;
    s.addFrame(target);
    s.advance(routine.durationMs);
    final summary = s.summary();
    expect(summary.outcomes.first.result.score, 100);
    // Other moves had no frames.
    expect(summary.outcomes.last.result.wasVisible, isFalse);
    expect(summary.totalScore, lessThan(100));
  });

  test('seed data references only valid joints and unique routine ids', () {
    final ids = builtInTrainers
        .expand((t) => t.routines)
        .map((r) => r.id)
        .toList();
    expect(ids.toSet().length, ids.length);
    for (final r in builtInTrainers.expand((t) => t.routines)) {
      for (final m in r.moves) {
        expect(m.target.angles, isNotEmpty);
        expect(m.durationMs, greaterThan(0));
        for (final a in m.target.angles.values) {
          expect(a, inInclusiveRange(0, 180));
        }
      }
    }
    expect(Joint.values, isNotEmpty);
  });
}

void submissionTests() {
  final routine = builtInTrainers.first.routines.first;

  test('toSubmission maps the summary to the submit_session shape', () {
    final s = WorkoutSession(routine);
    final target = Map.of(routine.moves.first.target.angles);
    final joint = target.keys.first;
    target[joint] = target[joint]! + 40;
    s.addFrame(target);
    s.advance(routine.durationMs);
    final summary = s.summary();
    final sub = summary.toSubmission(
      userId: 'u1',
      clientNonce: 'nonce',
      durationMs: 24123,
      playedAt: DateTime.utc(2026),
    );
    expect(sub.routineId, routine.id);
    expect(sub.score, summary.totalScore);
    expect(sub.durationMs, 24123);
    expect(sub.clientNonce, 'nonce');
    expect(sub.userId, 'u1');
    expect(sub.results.map((r) => r.moveIdx), [
      for (var i = 0; i < routine.moves.length; i++) i,
    ]);
    final first = sub.results.first;
    final result = summary.outcomes.first.result;
    expect(first.score, result.score);
    expect(first.worstJoint, result.worstJoint!.name);
    expect(first.deviation, result.worstSignedDeviation);
    // Unseen moves send explicit nulls.
    expect(sub.results.last.worstJoint, isNull);
    expect(sub.results.last.deviation, isNull);
  });
}
