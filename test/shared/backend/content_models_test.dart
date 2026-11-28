import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wiggle_move/app/theme.dart';
import 'package:wiggle_move/shared/backend/content_models.dart';
import 'package:wiggle_move/shared/backend/trainer_data.dart';
import 'package:wiggle_move/shared/pose/pose_math.dart';

import '../../support/content_fixture.dart';

/// Order-sensitive deep comparison via the cache encoding.
String _enc(List<Trainer> t) => jsonEncode(trainersToJson(t));

Map<String, Object?> _firstMove(List<Map<String, Object?>> rows) {
  final routines = rows[0]['routines']! as List;
  final moves = (routines[0] as Map)['moves'] as List;
  return moves[0] as Map<String, Object?>;
}

void main() {
  group('trainersFromRows (PostgREST shape)', () {
    test('seed.sql rows map to exactly the built-in content, sorted', () {
      final trainers = trainersFromRows(seedRows());
      expect(trainers.map((t) => t.id), ['mia', 'jay']);
      expect(trainers.first.routines.map((r) => r.id), [
        'pop-starter',
        'disco-fever',
      ]);
      expect(_enc(trainers), _enc(builtInTrainers));
    });

    test('color comes from the unsigned ARGB bigint', () {
      final mia = trainersFromRows(seedRows()).first;
      expect(mia.color.toARGB32(), 0xFFFF7F3F);
    });

    test('built-in colors match the theme and seed.sql', () {
      expect(builtInTrainers[0].color, AppColors.accent);
      expect(builtInTrainers[1].color, AppColors.secondary);
      expect(builtInTrainers[0].color.toARGB32(), 4294934335);
      expect(builtInTrainers[1].color.toARGB32(), 4279950273);
    });

    test('target_angles map joint names to degrees (int or double)', () {
      final t = targetFromJson({'leftKnee': 125, 'rightKnee': 124.5});
      expect(t.angles, {Joint.leftKnee: 125.0, Joint.rightKnee: 124.5});
      expect(targetToJson(t), {'leftKnee': 125.0, 'rightKnee': 124.5});
    });

    test('equal sort_order falls back to id order', () {
      final rows = seedRows();
      for (final t in rows) {
        t['sort_order'] = 0;
      }
      final mia = rows[1]['routines']! as List;
      for (final r in mia) {
        (r as Map)['sort_order'] = 0;
      }
      final trainers = trainersFromRows(rows);
      expect(trainers.map((t) => t.id), ['jay', 'mia']);
      expect(trainers.last.routines.map((r) => r.id), [
        'disco-fever',
        'pop-starter',
      ]);
      // Same result whatever the response order.
      final reversed = trainersFromRows(rows.reversed.toList());
      expect(_enc(reversed), _enc(trainers));
    });

    test('a non-list response is malformed', () {
      expect(() => trainersFromRows({'x': 1}), throwsFormatException);
      expect(() => trainersFromRows(null), throwsFormatException);
    });

    final malformed = <String, void Function(List<Map<String, Object?>>)>{
      'missing trainer name': (r) => r[0].remove('name'),
      'empty trainer name': (r) => r[0]['name'] = '',
      'blank trainer name': (r) => r[0]['name'] = '  ',
      'routine with no moves': (r) =>
          ((r[0]['routines']! as List)[0] as Map)['moves'] = <Object?>[],
      'color out of range': (r) => r[0]['color'] = 0x100000000,
      'negative color': (r) => r[0]['color'] = -1,
      'routines not a list': (r) => r[0]['routines'] = null,
      'unknown joint': (r) => _firstMove(r)['target_angles'] = {'nose': 10},
      'angle not a number': (r) =>
          _firstMove(r)['target_angles'] = {'leftKnee': '90'},
      'empty target': (r) => _firstMove(r)['target_angles'] = {},
      'zero duration': (r) => _firstMove(r)['duration_ms'] = 0,
      'missing idx': (r) => _firstMove(r).remove('idx'),
      'missing sort_order': (r) => r[1].remove('sort_order'),
    };
    for (final e in malformed.entries) {
      test('malformed: ${e.key} -> FormatException (no partial content)', () {
        final rows = seedRows();
        e.value(rows);
        expect(() => trainersFromRows(rows), throwsFormatException);
      });
    }
  });

  group('cache JSON', () {
    test('round-trips the built-in content', () {
      final json = jsonDecode(jsonEncode(trainersToJson(builtInTrainers)));
      expect(_enc(trainersFromJson(json)), _enc(builtInTrainers));
    });

    test('malformed cache JSON -> FormatException', () {
      expect(() => trainersFromJson('nope'), throwsFormatException);
      expect(
        () => trainersFromJson([
          {'id': 'x'},
        ]),
        throwsFormatException,
      );
    });
  });
}
