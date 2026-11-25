import 'package:flutter_test/flutter_test.dart';
import 'package:wiggle_move/features/scoring/move_scorer.dart';
import 'package:wiggle_move/features/scoring/pose_math.dart';

void main() {
  group('angleDeg', () {
    test('right angle', () {
      expect(
        angleDeg(const Pt(1, 0), const Pt(0, 0), const Pt(0, 1)),
        closeTo(90, 1e-9),
      );
    });
    test('straight line is 180', () {
      expect(
        angleDeg(const Pt(-1, 0), const Pt(0, 0), const Pt(1, 0)),
        closeTo(180, 1e-9),
      );
    });
    test('zero-length segment is null', () {
      expect(angleDeg(const Pt(0, 0), const Pt(0, 0), const Pt(1, 0)), isNull);
    });
  });

  test('measureAngles skips joints with missing landmarks', () {
    final angles = measureAngles({
      Lm.leftShoulder: const Pt(0, 0),
      Lm.leftElbow: const Pt(1, 0),
      Lm.leftWrist: const Pt(1, 1),
    });
    expect(angles.keys, [Joint.leftElbow]);
    expect(angles[Joint.leftElbow], closeTo(90, 1e-9));
  });

  group('MoveScorer', () {
    const target = MoveTarget({Joint.leftElbow: 90, Joint.rightElbow: 90});

    test('perfect pose scores 100 with no worst joint', () {
      final s = MoveScorer(target);
      s.addFrame({Joint.leftElbow: 90, Joint.rightElbow: 90});
      final r = s.finish();
      expect(r.score, 100);
      expect(r.worstJoint, isNull);
    });

    test('within tolerance still scores 100', () {
      final s = MoveScorer(target);
      s.addFrame({Joint.leftElbow: 100, Joint.rightElbow: 80});
      expect(s.finish().score, 100);
    });

    test('far-off joint is reported with direction', () {
      final s = MoveScorer(target);
      for (var i = 0; i < 4; i++) {
        s.addFrame({Joint.leftElbow: 90, Joint.rightElbow: 160});
      }
      final r = s.finish();
      expect(r.score, lessThan(100));
      expect(r.worstJoint, Joint.rightElbow);
      expect(r.worstSignedDeviation, closeTo(70, 1e-9));
      expect(Joint.rightElbow.hint(true), contains('bend'));
    });

    test('best half of frames is used (late arrival not punished)', () {
      final s = MoveScorer(target);
      s.addFrame({Joint.leftElbow: 170, Joint.rightElbow: 170});
      s.addFrame({Joint.leftElbow: 90, Joint.rightElbow: 90});
      expect(s.finish().score, 100);
    });

    test('no visible frames scores 0', () {
      final s = MoveScorer(target);
      expect(s.addFrame({}), isNull);
      final r = s.finish();
      expect(r.score, 0);
      expect(r.wasVisible, isFalse);
    });

    test('frames with under half the target joints visible are ignored', () {
      final s = MoveScorer(
        const MoveTarget({
          Joint.leftElbow: 90,
          Joint.rightElbow: 90,
          Joint.leftKnee: 90,
        }),
      );
      expect(s.addFrame({Joint.leftElbow: 90}), isNull);
    });
  });
}
