import 'package:flutter_test/flutter_test.dart';
import 'package:wiggle_move/features/scoring/pose_math.dart';
import 'package:wiggle_move/features/trainers/trainer_data.dart';
import 'package:wiggle_move/features/workout/workout_session.dart';

void main() {
  final routine = routineById('pop-starter')!;

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
    final ids = trainers.expand((t) => t.routines).map((r) => r.id).toList();
    expect(ids.toSet().length, ids.length);
    for (final r in trainers.expand((t) => t.routines)) {
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
