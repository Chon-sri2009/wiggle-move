import 'package:flutter_test/flutter_test.dart';
import 'package:wiggle_move/features/workout/workout_session.dart';
import 'package:wiggle_move/shared/backend/content_models.dart';
import 'package:wiggle_move/shared/pose/pose_math.dart';

const _squat = Move(
  name: 'Squat',
  instruction: 'sit',
  durationMs: 10000,
  target: MoveTarget({Joint.leftKnee: 95, Joint.rightKnee: 95}),
  rep: RepSpec(target: 3, joint: Joint.leftKnee, low: 110, high: 160),
);

const _pose = Move(
  name: 'Arms up',
  instruction: 'up',
  durationMs: 4000,
  target: MoveTarget({Joint.leftShoulder: 165}),
);

Routine _routine({
  List<Move> moves = const [_squat],
  int sets = 3,
  int rest = 5000,
}) => Routine(
  id: 'r',
  name: 'R',
  level: 'Easy',
  category: Routine.cardio,
  sets: sets,
  restMs: rest,
  moves: moves,
);

/// Feeds a full rep: down to the target pose, then standing again.
void _rep(WorkoutSession s) {
  s.addFrame({Joint.leftKnee: 95, Joint.rightKnee: 95});
  s.addFrame({Joint.leftKnee: 170, Joint.rightKnee: 170});
}

void main() {
  test('total duration is every set plus the rests between', () {
    final r = _routine(moves: [_squat, _pose]);
    expect(r.durationMs, 14000);
    expect(r.totalDurationMs, 14000 * 3 + 5000 * 2);
    expect(_routine(sets: 1).totalDurationMs, 10000);
  });

  test('timeline: set, rest, set, rest, set, done', () {
    final s = WorkoutSession(_routine());
    expect(s.setIndex, 0);
    expect(s.isResting, isFalse);
    s.advance(10000);
    expect(s.isResting, isTrue);
    expect(s.setIndex, 0);
    expect(s.currentMove, _squat); // the move that comes next
    expect(s.restRemainingMs, 5000);
    s.advance(12000);
    expect(s.restRemainingMs, 3000);
    s.advance(15000);
    expect(s.isResting, isFalse);
    expect(s.setIndex, 1);
    s.advance(25000);
    expect(s.isResting, isTrue);
    s.advance(30000);
    expect(s.setIndex, 2);
    expect(s.isDone, isFalse);
    s.advance(40000);
    expect(s.isDone, isTrue);
  });

  test('a late advance skips whole segments but loses no set', () {
    final s = WorkoutSession(_routine());
    s.advance(1 << 30);
    expect(s.isDone, isTrue);
    expect(s.summary().outcomes, hasLength(1));
  });

  test('reps are summed over sets; full reps keep the form score', () {
    final s = WorkoutSession(_routine());
    // Set ends at 10s, 25s, 40s; rests end at 15s and 30s.
    final marks = [10000, 15000, 25000, 30000, 40000];
    var m = 0;
    for (var set = 0; set < 3; set++) {
      for (var i = 0; i < 3; i++) {
        _rep(s);
      }
      expect(s.repCount, 3);
      s.advance(marks[m++]); // end of the set
      if (set < 2) s.advance(marks[m++]); // end of the rest
    }
    expect(s.isDone, isTrue);
    final summary = s.summary();
    final r = summary.outcomes.single.result;
    expect(r.reps, 9);
    expect(r.score, 100);
    expect(summary.totalReps, 9);
    expect(summary.targetReps, 9);
  });

  test('missing reps scale the set score down', () {
    final s = WorkoutSession(_routine(sets: 1));
    _rep(s); // 1 of 3 reps, perfect form
    s.advance(10000);
    final r = s.summary().outcomes.single.result;
    expect(r.reps, 1);
    expect(r.score, 33); // 100 * 1/3
  });

  test('extra reps beyond the target do not raise the score', () {
    final s = WorkoutSession(_routine(sets: 1));
    for (var i = 0; i < 6; i++) {
      _rep(s);
    }
    s.advance(10000);
    final r = s.summary().outcomes.single.result;
    expect(r.reps, 6);
    expect(r.score, 100);
  });

  test('reps are capped at the overshoot bound the server accepts', () {
    final s = WorkoutSession(_routine(sets: 1));
    for (var i = 0; i < 50; i++) {
      _rep(s); // a detection glitch: far more cycles than possible
    }
    expect(s.repCount, 50); // the live counter shows what was seen
    s.advance(10000);
    final r = s.summary().outcomes.single.result;
    expect(r.reps, 3 * maxRepsOvershoot); // target 3
    expect(r.score, 100); // the cap costs no score
  });

  test('frames during a rest are ignored', () {
    final s = WorkoutSession(_routine());
    s.advance(10000);
    expect(s.isResting, isTrue);
    expect(s.addFrame({Joint.leftKnee: 95, Joint.rightKnee: 95}), isNull);
    expect(s.repCount, 0);
  });

  test('the next set starts with a fresh counter', () {
    final s = WorkoutSession(_routine());
    _rep(s);
    expect(s.repCount, 1);
    s.advance(15000); // through the rest, into set 2
    expect(s.setIndex, 1);
    expect(s.repCount, 0);
  });

  test('a timed pose has no reps and is scored as before', () {
    final s = WorkoutSession(_routine(moves: [_pose], sets: 2, rest: 0));
    s.addFrame({Joint.leftShoulder: 165});
    s.advance(4000); // set 1 done, no rest segment (rest 0)
    expect(s.setIndex, 1);
    s.addFrame({Joint.leftShoulder: 165});
    s.advance(8000);
    final r = s.summary().outcomes.single.result;
    expect(r.reps, 0);
    expect(r.score, 100);
  });

  test('sets average the move score and keep the worst joint', () {
    final s = WorkoutSession(_routine(moves: [_pose], sets: 2, rest: 0));
    s.addFrame({Joint.leftShoulder: 165}); // perfect
    s.advance(4000);
    s.addFrame({Joint.leftShoulder: 165 - 60}); // 60 off, a bad set
    s.advance(8000);
    final r = s.summary().outcomes.single.result;
    expect(r.score, lessThan(100));
    expect(r.score, greaterThan(0));
    expect(r.worstJoint, Joint.leftShoulder);
    expect(r.worstSignedDeviation, -60);
    expect(r.frames, 2);
  });

  test('toSubmission carries sets and reps; totalScore stays the mean', () {
    final s = WorkoutSession(_routine(sets: 1));
    _rep(s);
    s.advance(10000);
    final sum = s.summary(durationMs: 10050);
    final sub = sum.toSubmission(
      userId: 'u',
      clientNonce: 'n',
      durationMs: 10050,
      playedAt: DateTime.utc(2026),
    );
    expect(sub.sets, 1);
    expect(sub.results.single.reps, 1);
    expect(sub.score, sum.totalScore);
    expect(sub.toPayload()['sets'], 1);
    expect(
      (sub.toPayload()['results'] as List).single,
      containsPair('reps', 1),
    );
    expect(sum.calories, 1); // 3.5 MET for 10 s is about 0.7 kcal
  });
}
