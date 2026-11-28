import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wiggle_move/shared/backend/leaderboard_repository.dart';
import 'package:wiggle_move/shared/backend/offline_leaderboard_repository.dart';
import 'package:wiggle_move/shared/backend/offline_sessions_repository.dart';

/// Wednesday 2026-11-25 12:00 UTC; the week started Monday 2026-11-23.
final _now = DateTime.utc(2026, 11, 25, 12);
final _thisWeek = DateTime.utc(2026, 11, 23, 0, 0, 1);
final _lastWeek = DateTime.utc(2026, 11, 22, 23, 59, 59);

LocalPlay _p(String name, String routine, int score, [DateTime? at]) =>
    LocalPlay(
      playerName: name,
      routineId: routine,
      score: score,
      playedAt: at ?? _thisWeek,
    );

List<String> _show(List<LeaderboardRow> rows) => [
  for (final r in rows)
    '${r.rank}:${r.displayName}:${r.score}${r.isMe ? '*' : ''}',
];

List<LeaderboardRow> _compute(
  List<LocalPlay> plays, {
  String? routineId,
  LeaderboardPeriod period = LeaderboardPeriod.all,
  int limit = 50,
  String? me,
}) => computeLocalLeaderboard(
  plays,
  routineId: routineId,
  period: period,
  limit: limit,
  me: me,
  now: _now,
);

void main() {
  group('computeLocalLeaderboard', () {
    test('per routine: best score per player, highest first', () {
      final rows = _compute([
        _p('Ann', 'a', 60),
        _p('Ann', 'a', 80),
        _p('Bo', 'a', 70),
        _p('Bo', 'b', 99),
      ], routineId: 'a');
      expect(_show(rows), ['1:Ann:80', '2:Bo:70']);
    });

    test('global: sum of each player best per routine', () {
      final rows = _compute([
        _p('Ann', 'a', 60),
        _p('Ann', 'a', 80),
        _p('Ann', 'b', 10),
        _p('Bo', 'a', 70),
        _p('Bo', 'b', 50),
      ]);
      expect(_show(rows), ['1:Bo:120', '2:Ann:90']);
    });

    test('ties share a rank and the next rank skips', () {
      final rows = _compute([
        _p('Cy', 'a', 50),
        _p('Bo', 'a', 90, DateTime.utc(2026, 11, 24)),
        _p('Ann', 'a', 90, DateTime.utc(2026, 11, 23, 1)),
        _p('Di', 'a', 90, DateTime.utc(2026, 11, 23, 1)),
      ], routineId: 'a');
      // Tie order: who reached the score first, then name.
      expect(_show(rows), ['1:Ann:90', '1:Di:90', '1:Bo:90', '4:Cy:50']);
    });

    test('week only counts plays since Monday 00:00 UTC', () {
      final plays = [
        _p('Ann', 'a', 95, _lastWeek),
        _p('Ann', 'a', 40),
        _p('Bo', 'a', 60, _lastWeek),
      ];
      expect(_show(_compute(plays, period: LeaderboardPeriod.week)), [
        '1:Ann:40',
      ]);
      expect(_show(_compute(plays)), ['1:Ann:95', '2:Bo:60']);
    });

    test('week boundary uses UTC even for local-time plays', () {
      final local = DateTime.utc(2026, 11, 23).toLocal();
      final rows = _compute([
        _p('Ann', 'a', 10, local),
      ], period: LeaderboardPeriod.week);
      expect(_show(rows), ['1:Ann:10']);
    });

    test('marks the signed-in player', () {
      final rows = _compute([_p('Ann', 'a', 10), _p('Bo', 'a', 20)], me: 'Ann');
      expect(_show(rows), ['1:Bo:20', '2:Ann:10*']);
    });

    test('appends my row when outside the top', () {
      final rows = _compute(
        [_p('Ann', 'a', 10), _p('Bo', 'a', 30), _p('Cy', 'a', 20)],
        limit: 1,
        me: 'Ann',
      );
      expect(_show(rows), ['1:Bo:30', '3:Ann:10*']);
    });

    test('limit is clamped to 1..100', () {
      final plays = [_p('Ann', 'a', 10), _p('Bo', 'a', 30)];
      expect(_compute(plays, limit: 0), hasLength(1));
      final many = [for (var i = 0; i < 120; i++) _p('P$i', 'a', i)];
      expect(_compute(many, limit: 500), hasLength(100));
    });

    test('no plays is an empty board', () {
      expect(_compute(const []), isEmpty);
    });

    test('blank names show as Player', () {
      expect(_show(_compute([_p('  ', 'a', 5)])), ['1:Player:5']);
    });
  });

  group('OfflineLeaderboardRepository', () {
    Future<OfflineLeaderboardRepository> repo(
      Map<String, Object> values, {
      String? me = 'Ann',
    }) async {
      SharedPreferences.setMockInitialValues(values);
      return OfflineLeaderboardRepository(
        await SharedPreferences.getInstance(),
        playerName: () => me,
        routineIdsIn: (category) async => category == 'cardio' ? {'b'} : {'a'},
        now: () => _now,
      );
    }

    test('a category counts only the routines of that category', () async {
      final r = await repo({
        localLeaderboardKey: jsonEncode([
          _p('Ann', 'a', 70).toJson(),
          _p('Ann', 'b', 40).toJson(),
          _p('Bo', 'b', 60).toJson(),
        ]),
      });
      // 'b' is the cardio routine: Bo 60 beats Ann 40; Ann's dance 70 is out.
      expect(
        _show(await r.fetch(period: LeaderboardPeriod.all, category: 'cardio')),
        ['1:Bo:60', '2:Ann:40*'],
      );
      expect(
        _show(await r.fetch(period: LeaderboardPeriod.all, category: 'dance')),
        ['1:Ann:70*'],
      );
      // No category: everything, as before (Ann 70 + 40 = 110).
      expect(_show(await r.fetch(period: LeaderboardPeriod.all)), [
        '1:Ann:110*',
        '2:Bo:60',
      ]);
    });

    test('reads the plays stored by OfflineSessionsRepository', () async {
      final r = await repo({
        localLeaderboardKey: jsonEncode([
          _p('Ann', 'a', 70).toJson(),
          _p('Bo', 'a', 80).toJson(),
        ]),
      });
      expect(_show(await r.fetch(period: LeaderboardPeriod.all)), [
        '1:Bo:80',
        '2:Ann:70*',
      ]);
    });

    test('skips malformed entries and survives corrupt storage', () async {
      final r = await repo({
        localLeaderboardKey: jsonEncode([
          {'playerName': 'Ann'},
          'x',
          _p('Bo', 'a', 80).toJson(),
        ]),
      });
      expect(_show(await r.fetch(period: LeaderboardPeriod.all)), ['1:Bo:80']);
      for (final bad in <Object>['{not json', '{"a":1}', 42]) {
        final r = await repo({localLeaderboardKey: bad});
        expect(await r.fetch(period: LeaderboardPeriod.all), isEmpty);
      }
    });
  });

  test('LocalPlay round-trips and rejects bad shapes', () {
    final p = _p('Ann', 'a', 70);
    final back = LocalPlay.tryFromJson(p.toJson())!;
    expect(
      (back.playerName, back.routineId, back.score, back.playedAt),
      (p.playerName, p.routineId, p.score, p.playedAt),
    );
    expect(LocalPlay.tryFromJson({...p.toJson(), 'score': '7'}), isNull);
    expect(LocalPlay.tryFromJson({...p.toJson(), 'playedAt': 'x'}), isNull);
    expect(LocalPlay.tryFromJson(null), isNull);
  });
}
