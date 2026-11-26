import 'profile_repository.dart';

/// Leaderboard time window. [name] is the wire value of `p_period`.
enum LeaderboardPeriod {
  /// Since Monday 00:00 UTC.
  week,

  /// Every stored play.
  all,
}

/// One row of `public.leaderboard(...)`. Ties share a [rank] (the next rank
/// skips), exactly as the server returns it.
class LeaderboardRow {
  const LeaderboardRow({
    required this.rank,
    required this.displayName,
    required this.score,
    required this.isMe,
    this.avatar,
  });

  final int rank;
  final String displayName;
  final String? avatar;
  final int score;

  /// The signed-in user's own row.
  final bool isMe;
}

/// Parses the `leaderboard` function result. Any malformed row fails the
/// whole fetch (a half board would rank people wrongly).
List<LeaderboardRow> leaderboardRowsFromJson(Object? json) {
  const bad = RepositoryFailure(RepositoryFailure.generic);
  if (json is! List) throw bad;
  return [
    for (final row in json)
      if (row is Map &&
          row['rank'] is int &&
          row['display_name'] is String &&
          row['score'] is int &&
          row['is_me'] is bool &&
          (row['avatar'] == null || row['avatar'] is String))
        LeaderboardRow(
          rank: row['rank'] as int,
          displayName: row['display_name'] as String,
          avatar: row['avatar'] as String?,
          score: row['score'] as int,
          isMe: row['is_me'] as bool,
        )
      else
        throw bad,
  ];
}

/// Ranked scores. Implementations: `SupabaseLeaderboardRepository` (the
/// `leaderboard` database function) and `OfflineLeaderboardRepository`
/// (WM_OFFLINE, plays stored on this device).
///
/// [fetch] throws [RepositoryFailure] on error.
abstract class LeaderboardRepository {
  /// Top [limit] rows for [routineId] (global when null) in [period], plus
  /// the caller's own row when it is outside the top.
  Future<List<LeaderboardRow>> fetch({
    String? routineId,
    required LeaderboardPeriod period,
    int limit = 50,
  });
}
