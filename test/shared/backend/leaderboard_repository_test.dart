import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:wiggle_move/shared/backend/leaderboard_repository.dart';
import 'package:wiggle_move/shared/backend/profile_repository.dart';
import 'package:wiggle_move/shared/backend/supabase_leaderboard_repository.dart';

Map<String, Object?> _row({
  Object? rank = 1,
  Object? name = 'Ann',
  Object? avatar,
  Object? score = 90,
  Object? isMe = false,
}) => {
  'rank': rank,
  'display_name': name,
  'avatar': avatar,
  'score': score,
  'is_me': isMe,
};

void main() {
  group('leaderboardRowsFromJson', () {
    test('parses valid rows in server order', () {
      final rows = leaderboardRowsFromJson([
        _row(rank: 1, name: 'Ann', score: 90, avatar: 'a.png'),
        _row(rank: 1, name: 'Bo', score: 90, isMe: true),
        _row(rank: 3, name: 'Cy', score: 10),
      ]);
      expect(rows.map((r) => '${r.rank}:${r.displayName}:${r.score}'), [
        '1:Ann:90',
        '1:Bo:90',
        '3:Cy:10',
      ]);
      expect(rows.first.avatar, 'a.png');
      expect(rows[1].avatar, isNull);
      expect(rows.map((r) => r.isMe), [false, true, false]);
    });

    test('an empty list is an empty board', () {
      expect(leaderboardRowsFromJson(const []), isEmpty);
    });

    final malformed = <String, Object?>{
      'not a list': {'rank': 1},
      'null body': null,
      'row not a map': ['x'],
      'rank as string': [_row(rank: '1')],
      'rank missing': [
        {'display_name': 'Ann', 'score': 1, 'is_me': false},
      ],
      'name null': [_row(name: null)],
      'score as double': [_row(score: 1.5)],
      'is_me null': [_row(isMe: null)],
      'avatar as int': [_row(avatar: 3)],
      'one bad row among good': [_row(), _row(score: null)],
    };
    for (final MapEntry(:key, :value) in malformed.entries) {
      test('malformed ($key) fails the whole fetch', () {
        expect(
          () => leaderboardRowsFromJson(value),
          throwsA(
            isA<RepositoryFailure>().having(
              (f) => f.message,
              'message',
              RepositoryFailure.generic,
            ),
          ),
        );
      });
    }
  });

  group('SupabaseLeaderboardRepository', () {
    late List<(String, Map<String, Object?>)> calls;
    SupabaseLeaderboardRepository repo(FutureOr<Object?> Function() answer) {
      calls = [];
      return SupabaseLeaderboardRepository.withRpc((fn, params) async {
        calls.add((fn, params));
        return answer();
      });
    }

    test('calls the leaderboard function with wire params', () async {
      final r = repo(() => [_row()]);
      final rows = await r.fetch(
        routineId: 'mia-pop',
        period: LeaderboardPeriod.week,
        limit: 20,
      );
      expect(rows.single.displayName, 'Ann');
      expect(calls.single.$1, 'leaderboard');
      expect(calls.single.$2, {
        'p_routine_id': 'mia-pop',
        'p_period': 'week',
        'p_limit': 20,
      });
    });

    test('global all-time sends a null routine and the defaults', () async {
      final r = repo(() => const []);
      await r.fetch(period: LeaderboardPeriod.all);
      expect(calls.single.$2, {
        'p_routine_id': null,
        'p_period': 'all',
        'p_limit': 50,
      });
    });

    test('a malformed response is a generic failure', () async {
      final r = repo(() => {'oops': true});
      await expectLater(
        r.fetch(period: LeaderboardPeriod.all),
        throwsA(
          isA<RepositoryFailure>().having(
            (f) => f.message,
            'message',
            RepositoryFailure.generic,
          ),
        ),
      );
    });

    final errors = <String, (Object, String)>{
      'socket': (const SocketException('down'), RepositoryFailure.network),
      'timeout': (TimeoutException('slow'), RepositoryFailure.network),
      'expired JWT': (
        const PostgrestException(message: 'JWT expired', code: 'PGRST301'),
        RepositoryFailure.sessionExpired,
      ),
      'invalid period (22023)': (
        const PostgrestException(message: 'invalid period', code: '22023'),
        RepositoryFailure.generic,
      ),
      'permission denied': (
        const PostgrestException(message: 'denied', code: '42501'),
        RepositoryFailure.generic,
      ),
      'anything else': (StateError('x'), RepositoryFailure.generic),
    };
    for (final MapEntry(:key, value: (error, message)) in errors.entries) {
      test('$key maps to a safe failure', () async {
        final r = repo(() => throw error);
        await expectLater(
          r.fetch(period: LeaderboardPeriod.all),
          throwsA(
            isA<RepositoryFailure>().having((f) => f.message, 'msg', message),
          ),
        );
      });
    }

    test('a hung request times out as a network failure', () async {
      final r = SupabaseLeaderboardRepository.withRpc(
        (fn, params) => Completer<Object?>().future,
        timeout: const Duration(milliseconds: 10),
      );
      await expectLater(
        r.fetch(period: LeaderboardPeriod.all),
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
}
