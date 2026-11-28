import 'package:flutter_test/flutter_test.dart';
import 'package:wiggle_move/shared/backend/content_models.dart';
import 'package:wiggle_move/shared/backend/trainer_data.dart';
import 'package:wiggle_move/shared/pose/pose_math.dart';

Map<String, Object?> _move({Map<String, Object?> extra = const {}}) => {
  'name': 'Squats',
  'instruction': 'sit',
  'duration_ms': 30000,
  'target_angles': {'leftKnee': 95},
  ...extra,
};

Map<String, Object?> _routine({
  Map<String, Object?> extra = const {},
  List<Object?>? moves,
}) => {
  'id': 'r',
  'name': 'R',
  'level': 'Easy',
  'moves': moves ?? [_move()],
  ...extra,
};

const _rep = {
  'reps': 12,
  'rep_joint': 'leftKnee',
  'rep_low': 110,
  'rep_high': 160,
};

void main() {
  group('routine cardio fields', () {
    test('missing keys (old cache / DB without the migration) default', () {
      final r = Routine.fromJson(_routine());
      expect(r.category, Routine.dance);
      expect(r.sets, 1);
      expect(r.restMs, 0);
      expect(r.met, 3.5);
      expect(r.moves.single.rep, isNull);
    });

    test('values round trip through the cache encoding', () {
      final r = Routine.fromJson(
        _routine(
          extra: {'category': 'cardio', 'sets': 3, 'rest_ms': 20000, 'met': 8},
          moves: [_move(extra: _rep)],
        ),
      );
      expect(r.isCardio, isTrue);
      expect(r.sets, 3);
      expect(r.restMs, 20000);
      expect(r.met, 8.0);
      final rep = r.moves.single.rep!;
      expect(rep.target, 12);
      expect(rep.joint, Joint.leftKnee);
      expect(rep.low, 110);
      expect(rep.high, 160);
      final again = Routine.fromJson(r.toJson());
      expect(again.toJson(), r.toJson());
    });

    final bad = <String, Map<String, Object?>>{
      'unknown category': {'category': 'yoga'},
      'zero sets': {'sets': 0},
      'sets as string': {'sets': '3'},
      'negative rest': {'rest_ms': -1},
      'zero met': {'met': 0},
      'huge met': {'met': 99},
    };
    for (final MapEntry(:key, :value) in bad.entries) {
      test('$key is malformed', () {
        expect(
          () => Routine.fromJson(_routine(extra: value)),
          throwsFormatException,
        );
      });
    }
  });

  group('move rep fields', () {
    test('all-null rep columns (a DB row of a timed pose) mean no reps', () {
      final m = Move.fromJson(
        _move(
          extra: {
            'reps': null,
            'rep_joint': null,
            'rep_low': null,
            'rep_high': null,
          },
        ),
      );
      expect(m.rep, isNull);
    });

    final bad = <String, Map<String, Object?>>{
      'rep fields without reps': {'rep_joint': 'leftKnee'},
      'zero reps': {..._rep, 'reps': 0},
      'missing joint': {..._rep, 'rep_joint': null},
      'unknown joint': {..._rep, 'rep_joint': 'leftEar'},
      'low not below high': {..._rep, 'rep_low': 160},
      'missing thresholds': {'reps': 5, 'rep_joint': 'leftKnee'},
    };
    for (final MapEntry(:key, :value) in bad.entries) {
      test('$key is malformed', () {
        expect(() => Move.fromJson(_move(extra: value)), throwsFormatException);
      });
    }
  });

  test('built-in cardio routines are consistent', () {
    final cardio = builtInTrainers
        .expand((t) => t.routines)
        .where((r) => r.isCardio)
        .toList();
    expect(cardio.map((r) => r.id), contains('squat-sets'));
    for (final r in cardio.where((r) => r.sets > 1)) {
      expect(r.restMs, greaterThan(0), reason: r.id);
      expect(r.moves.any((m) => m.rep != null), isTrue, reason: r.id);
    }
    for (final m in builtInTrainers.expand(
      (t) => t.routines.expand((r) => r.moves),
    )) {
      final rep = m.rep;
      if (rep == null) continue;
      expect(rep.low, lessThan(rep.high));
      // The rep joint must be one the move is judged on.
      expect(m.target.angles.keys, contains(rep.joint), reason: m.name);
    }
  });
}
