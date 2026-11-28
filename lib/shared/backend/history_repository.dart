import 'profile_repository.dart';
import 'sessions_repository.dart';

/// One stored play of the signed-in user.
class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.routineId,
    required this.score,
    required this.durationMs,
    required this.playedAt,
    required this.results,
    this.sets = 1,
  });

  final String id;
  final String routineId;
  final int score;
  final int durationMs;
  final DateTime playedAt;

  /// Sets played (1 for plays stored on this device).
  final int sets;

  /// Per-move results by move index (empty when only the total was stored,
  /// as for plays kept on this device under WM_OFFLINE).
  final List<MoveSubmission> results;
}

/// Parses the `sessions` rows with embedded `move_results`. Any malformed
/// row fails the whole fetch rather than silently dropping plays.
List<HistoryEntry> historyEntriesFromJson(Object? json) {
  const bad = RepositoryFailure(RepositoryFailure.generic);
  if (json is! List) throw bad;
  return [
    for (final row in json)
      () {
        if (row is! Map) throw bad;
        final id = row['id'], routine = row['routine_id'];
        final score = row['score'], duration = row['duration_ms'];
        final at = row['played_at'], rawResults = row['move_results'];
        final sets = row['sets'];
        if (sets is! int ||
            sets < 1 ||
            id is! String ||
            routine is! String ||
            score is! int ||
            duration is! int ||
            at is! String ||
            rawResults is! List) {
          throw bad;
        }
        final playedAt = DateTime.tryParse(at);
        if (playedAt == null) throw bad;
        final results = [
          for (final r in rawResults)
            MoveSubmission.tryFromJson(r) ?? (throw bad),
        ]..sort((a, b) => a.moveIdx.compareTo(b.moveIdx));
        return HistoryEntry(
          id: id,
          routineId: routine,
          score: score,
          durationMs: duration,
          playedAt: playedAt,
          sets: sets,
          results: results,
        );
      }(),
  ];
}

/// The signed-in user's past plays, newest first. Implementations:
/// `SupabaseHistoryRepository` (own rows only, by RLS) and
/// `OfflineHistoryRepository` (WM_OFFLINE).
///
/// [fetch] throws [RepositoryFailure] on error.
abstract class HistoryRepository {
  Future<List<HistoryEntry>> fetch({int limit = 50});
}
