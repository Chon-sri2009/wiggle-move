import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wiggle_move/features/scoring/move_scorer.dart';
import 'package:wiggle_move/features/workout/live_advice.dart';
import 'package:wiggle_move/features/workout/reference/reference_clip.dart';
import 'package:wiggle_move/features/workout/workout_session.dart';
import 'package:wiggle_move/shared/backend/content_models.dart';
import 'package:wiggle_move/shared/backend/demo_content.dart';
import 'package:wiggle_move/shared/pose/angle_smoother.dart';
import 'package:wiggle_move/shared/pose/pose_math.dart';

ReferenceClip _clip() => ReferenceClip.fromJson(
  jsonDecode(File('assets/reference/squat.timeline.json').readAsStringSync()),
);

void main() {
  group('ReferenceClip', () {
    test('loads the squat timeline', () {
      final clip = _clip();
      expect(clip.sampleCount, 949);
      expect(clip.seconds, closeTo(189.72, 0.05));
    });

    test('a user matching the trainer is judged against the same pose', () {
      final clip = _clip();
      final trainer = clip.targetAt(2000, {})!;
      expect(trainer, isNotEmpty);
      final target = clip.targetAt(2000, trainer)!;
      for (final e in trainer.entries) {
        expect(target[e.key], closeTo(e.value, 1e-9));
      }
    });

    test('being a beat late is not punished: the lagging pose is chosen', () {
      final clip = _clip();
      final earlier = clip.targetAt(
        1500,
        {},
      )!; // what the trainer did 0.5 s ago
      final target = clip.targetAt(2000, earlier)!;
      for (final e in earlier.entries) {
        expect(target[e.key], closeTo(e.value, 1e-9));
      }
    });

    test('offsets outside the clip are clamped', () {
      final clip = _clip();
      expect(clip.targetAt(-5000, {}), isNotNull);
      expect(clip.targetAt(60000, {}), isNotNull);
    });
  });

  group('LiveAdvice', () {
    test('warns only after 3 frames in a row, with the joint hint', () {
      final a = LiveAdvice();
      expect(a.add(Joint.leftKnee, 40), isNull);
      expect(a.add(Joint.leftKnee, 40), isNull);
      expect(a.add(Joint.leftKnee, 40), 'Bend your left knee more');
    });

    test('too small an angle asks to straighten', () {
      final a = LiveAdvice();
      for (var i = 0; i < 3; i++) {
        a.add(Joint.rightElbow, -50);
      }
      expect(a.message, 'Straighten your right elbow');
    });

    test('a changing joint restarts the count', () {
      final a = LiveAdvice();
      a.add(Joint.leftKnee, 40);
      a.add(Joint.leftKnee, 40);
      expect(a.add(Joint.rightKnee, 40), isNull);
    });

    test('clears after 2 good frames, not 1', () {
      final a = LiveAdvice();
      for (var i = 0; i < 3; i++) {
        a.add(Joint.leftKnee, 40);
      }
      expect(a.add(null, 0), isNotNull);
      expect(a.add(null, 0), isNull);
    });
  });

  group('workout judged against the trainer video', () {
    final routine = demoTrainer.routines.firstWhere(
      (r) => r.id == demoRoutineId,
    );

    // One set, so the score is not averaged with a set nobody played.
    final oneSet = Routine(
      id: routine.id,
      name: routine.name,
      level: routine.level,
      moves: routine.moves,
    );
    WorkoutSession oneSetSession() =>
        WorkoutSession(oneSet)..reference = _clip();

    test('following the trainer scores high and shows no warning', () {
      final s = oneSetSession();
      for (var t = 1000; t <= 3000; t += 100) {
        s.advance(t);
        final trainer = s.reference!.targetAt(t, {})!;
        s.addFrame(trainer);
      }
      expect(s.advice, isNull);
      s.advance(oneSet.totalDurationMs);
      expect(s.summary().outcomes.first.result.score, greaterThan(90));
    });

    test('moving far from the trainer lowers the score and gives advice', () {
      final s = oneSetSession();
      for (var t = 1000; t <= 3000; t += 100) {
        s.advance(t);
        final trainer = s.reference!.targetAt(t, {})!;
        s.addFrame({for (final e in trainer.entries) e.key: e.value + 150});
      }
      expect(s.advice, isNotNull);
      expect(s.advice, isNot(isEmpty));
      s.advance(oneSet.totalDurationMs);
      expect(s.summary().outcomes.first.result.score, lessThan(40));
    });

    test('the trainer clip restarts with the second set', () {
      final twoSets = Routine(
        id: routine.id,
        name: routine.name,
        level: routine.level,
        sets: 2,
        restMs: routine.restMs,
        moves: routine.moves,
      );
      final s = WorkoutSession(twoSets)..reference = _clip();
      // 100 ms into set 2 the offset is 100, not past the clip end: frames still score.
      final setTwoStart = twoSets.durationMs + twoSets.restMs;
      s.advance(setTwoStart + 100);
      expect(s.isResting, isFalse);
      expect(s.setIndex, 1);
      final trainer = s.reference!.targetAt(100, {})!;
      expect(s.addFrame(trainer), greaterThan(0.9));
    });
  });

  group('MoveScorer', () {
    test('tracks the worst joint of the last frame', () {
      final scorer = MoveScorer(
        const MoveTarget({Joint.leftKnee: 90, Joint.rightKnee: 90}),
      );
      scorer.addFrame({Joint.leftKnee: 91, Joint.rightKnee: 170});
      expect(scorer.lastWorst, Joint.rightKnee);
      expect(scorer.lastWorstSigned, 80);
      scorer.addFrame({Joint.leftKnee: 91, Joint.rightKnee: 92});
      expect(scorer.lastWorst, isNull);
    });

    test('a per-frame target replaces the fixed one', () {
      final scorer = MoveScorer(const MoveTarget({Joint.leftKnee: 90}));
      final score = scorer.addFrame({
        Joint.leftKnee: 170,
      }, against: const MoveTarget({Joint.leftKnee: 170}));
      expect(score, 1);
    });
  });

  group('AngleSmoother', () {
    test('damps single-frame outlier spikes and resets after absence', () {
      final s = AngleSmoother(alpha: 0.5, maxJumpDeg: 60, maxMissingFrames: 2);
      expect(s.add({Joint.leftKnee: 100})[Joint.leftKnee], 100);
      // A sudden 80-degree spike is heavily damped (k = 0.125 -> 110).
      expect(s.add({Joint.leftKnee: 180})[Joint.leftKnee], closeTo(110, 1e-6));
      // Normal step back to 100 settles smoothly.
      expect(s.add({Joint.leftKnee: 100})[Joint.leftKnee], closeTo(105, 1e-6));

      // Missing for > maxMissingFrames clears the joint's history.
      for (var i = 0; i < 3; i++) {
        expect(s.add({}), isEmpty);
      }
      expect(s.add({Joint.leftKnee: 160})[Joint.leftKnee], 160);
    });
  });
}
