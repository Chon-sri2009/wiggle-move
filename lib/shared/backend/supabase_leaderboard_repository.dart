import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import 'leaderboard_repository.dart';
import 'profile_repository.dart';

/// Calls a Postgres function by name (`SupabaseClient.rpc`).
typedef LeaderboardRpc = Future<Object?> Function(
  String fn,
  Map<String, Object?> params,
);

/// Reads the `leaderboard` security-definer function (WM-09). It is
/// executable only by signed-in users and returns no user ids.
class SupabaseLeaderboardRepository implements LeaderboardRepository {
  SupabaseLeaderboardRepository(SupabaseClient client)
    : this.withRpc((fn, params) => client.rpc<Object?>(fn, params: params));

  SupabaseLeaderboardRepository.withRpc(
    this._rpc, {
    this.timeout = const Duration(seconds: 20),
  });

  static const functionName = 'leaderboard';

  final LeaderboardRpc _rpc;
  final Duration timeout;

  @override
  Future<List<LeaderboardRow>> fetch({
    String? routineId,
    required LeaderboardPeriod period,
    int limit = 50,
    String? category,
  }) async {
    try {
      final data = await _rpc(functionName, {
        'p_routine_id': routineId,
        'p_period': period.name,
        'p_limit': limit,
        'p_category': category,
      }).timeout(timeout);
      return leaderboardRowsFromJson(data);
    } catch (e) {
      throw mapRepositoryException(e);
    }
  }
}
