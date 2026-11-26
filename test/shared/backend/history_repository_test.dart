import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wiggle_move/shared/backend/history_repository.dart';
import 'package:wiggle_move/shared/backend/offline_history_repository.dart';
import 'package:wiggle_move/shared/backend/offline_sessions_repository.dart';
import 'package:wiggle_move/shared/backend/profile_repository.dart';
import 'package:wiggle_move/shared/backend/supabase_history_repository.dart';

Map<String, Object?> _row({
  Object? id = 's1',
  Object? routine = 'pop-starter',
  Object? score = 80,
  Object? duration = 24000,
  Object? at = '2026-11-25T12:00:00+00:00',
  Object? results,
}) => {
  'id': id,
  'routine_id': routine,
  'score': score,
  'duration_ms': duration,
  'played_at': at,
  'move_results':
      results ??
      [
        {
          'move_idx': 1,
          'score': 60,
          'worst_joint': 'leftKnee',
          'deviation': 12,
        },
        {'move_idx': 0, 'score': 90, 'worst_joint': null, 'deviation': null},
      ],
};

Matcher _generic() => throwsA(
  isA<RepositoryFailure>().having(
    (f) => f.message,
    'message',
    RepositoryFailure.generic,
  ),
);

void main() {
  group('historyEntriesFromJson', () {
    test('parses rows and orders move results by index', () {
      final entries = historyEntriesFromJson([_row(), _row(id: 's2')]);
      expect(entries.map((e) => e.id), ['s1', 's2']);
      final e = entries.first;
      expect(e.routineId, 'pop-starter');
      expect(e.score, 80);
      expect(e.durationMs, 24000);
      expect(e.playedAt, DateTime.utc(2026, 11, 25, 12));
      expect(e.results.map((r) => r.moveIdx), [0, 1]);
      expect(e.results[1].worstJoint, 'leftKnee');
      expect(e.results[1].deviation, 12.0); // int from the server -> double
    });

    test('an empty list is empty history', () {
      expect(historyEntriesFromJson(const []), isEmpty);
    });

    final malformed = <String, Object?>{
      'not a list': {'a': 1},
      'row not a map': ['x'],
      'id null': [_row(id: null)],
      'score as string': [_row(score: '8')],
      'duration null': [_row(duration: null)],
      'bad date': [_row(at: 'yesterday')],
      'results missing': [
        {
          'id': 's',
          'routine_id': 'r',
          'score': 1,
          'duration_ms': 1,
          'played_at': '2026-01-01T00:00:00Z',
        },
      ],
      'bad result row': [
        _row(
          results: [
            {'move_idx': 'a', 'score': 1},
          ],
        ),
      ],
    };
    for (final MapEntry(:key, :value) in malformed.entries) {
      test('malformed ($key) fails the whole fetch', () {
        expect(() => historyEntriesFromJson(value), _generic());
      });
    }
  });

  group('SupabaseHistoryRepository', () {
    test('asks for the limit and parses the rows', () async {
      int? asked;
      final repo = SupabaseHistoryRepository.withQuery((limit) async {
        asked = limit;
        return [_row()];
      });
      expect((await repo.fetch(limit: 20)).single.id, 's1');
      expect(asked, 20);
      await repo.fetch(limit: 5000);
      expect(asked, 100);
    });

    test('errors map to safe failures', () async {
      Future<Object?> run(Object error) =>
          SupabaseHistoryRepository.withQuery((_) async => throw error)
              .fetch()
              .then<Object?>((_) => null, onError: (Object e) => e);
      expect(
        (await run(const SocketException('down')) as RepositoryFailure).message,
        RepositoryFailure.network,
      );
      expect(
        (await run(StateError('x')) as RepositoryFailure).message,
        RepositoryFailure.generic,
      );
    });

    test('a malformed response is a generic failure', () async {
      final repo = SupabaseHistoryRepository.withQuery(
        (_) async => {'oops': true},
      );
      await expectLater(repo.fetch(), _generic());
    });

    test('a hung request times out as a network failure', () async {
      final repo = SupabaseHistoryRepository.withQuery(
        (_) => Completer<Object?>().future,
        timeout: const Duration(milliseconds: 10),
      );
      await expectLater(
        repo.fetch(),
        throwsA(
          isA<RepositoryFailure>().having(
            (f) => f.message,
            'message',
            RepositoryFailure.network,
          ),
        ),
      );
    });
  });

  group('OfflineHistoryRepository', () {
    Future<OfflineHistoryRepository> repo(
      List<LocalPlay> plays, {
      String? me = 'Ann',
    }) async {
      SharedPreferences.setMockInitialValues({
        localLeaderboardKey: jsonEncode([for (final p in plays) p.toJson()]),
      });
      return OfflineHistoryRepository(
        await SharedPreferences.getInstance(),
        playerName: () => me,
      );
    }

    LocalPlay play(String name, int score, int day) => LocalPlay(
      playerName: name,
      routineId: 'pop-starter',
      score: score,
      playedAt: DateTime.utc(2026, 11, day),
    );

    test('lists only my plays, newest first, without move details', () async {
      final r = await repo([
        play('Ann', 10, 1),
        play('Bo', 99, 2),
        play('Ann', 30, 3),
        play(' Ann ', 20, 2),
      ]);
      final entries = await r.fetch();
      expect(entries.map((e) => e.score), [30, 20, 10]);
      expect(entries.every((e) => e.results.isEmpty), isTrue);
      expect(entries.map((e) => e.id).toSet(), hasLength(3));
    });

    test('limits the list', () async {
      final r = await repo([for (var d = 1; d <= 5; d++) play('Ann', d, d)]);
      expect(await r.fetch(limit: 2), hasLength(2));
    });

    test('no signed-in name or no plays is empty history', () async {
      expect(
        await (await repo([play('Ann', 1, 1)], me: null)).fetch(),
        isEmpty,
      );
      expect(await (await repo(const [])).fetch(), isEmpty);
    });
  });
}
