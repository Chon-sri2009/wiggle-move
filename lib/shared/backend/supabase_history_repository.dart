import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import 'history_repository.dart';
import 'profile_repository.dart';

/// Runs the history query for the most recent [limit] plays.
typedef HistoryQuery = Future<Object?> Function(int limit);

/// Reads the user's own `sessions` with their `move_results` (RLS limits
/// both tables to the signed-in user), newest first.
class SupabaseHistoryRepository implements HistoryRepository {
  SupabaseHistoryRepository(SupabaseClient client)
    : this.withQuery(
        (limit) => client
            .from('sessions')
            .select(
              'id, routine_id, score, duration_ms, played_at, sets, '
              'move_results(move_idx, score, reps, worst_joint, deviation)',
            )
            .order('played_at', ascending: false)
            .limit(limit),
      );

  SupabaseHistoryRepository.withQuery(
    this._query, {
    this.timeout = const Duration(seconds: 20),
  });

  final HistoryQuery _query;
  final Duration timeout;

  @override
  Future<List<HistoryEntry>> fetch({int limit = 50}) async {
    try {
      final data = await _query(limit.clamp(1, 100)).timeout(timeout);
      return historyEntriesFromJson(data);
    } catch (e) {
      throw mapRepositoryException(e);
    }
  }
}
