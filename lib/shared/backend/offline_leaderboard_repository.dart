import 'package:shared_preferences/shared_preferences.dart';

import 'leaderboard_repository.dart';
import 'offline_sessions_repository.dart';

/// Ranks [plays] the way `public.leaderboard(...)` does, for WM_OFFLINE.
///
/// Per routine a player's score is their best play; globally it is the sum
/// of their best per routine. Ties share a rank (the next rank skips) and
/// are listed by who reached the score first, then by name. The top [limit]
/// (1..100) are returned, plus [me] when outside them. [period] `week` keeps
/// plays since Monday 00:00 UTC of [now]. [routineIds], when given, keeps
/// only plays of those routines (a category).
List<LeaderboardRow> computeLocalLeaderboard(
  List<LocalPlay> plays, {
  String? routineId,
  Set<String>? routineIds,
  required LeaderboardPeriod period,
  required int limit,
  required String? me,
  required DateTime now,
}) {
  final since = period == LeaderboardPeriod.week ? _weekStart(now) : null;
  // player -> routine -> best play
  final best = <String, Map<String, LocalPlay>>{};
  for (final p in plays) {
    if (routineId != null && p.routineId != routineId) continue;
    if (routineIds != null && !routineIds.contains(p.routineId)) continue;
    if (since != null && p.playedAt.toUtc().isBefore(since)) continue;
    final mine = best.putIfAbsent(_name(p.playerName), () => {});
    final current = mine[p.routineId];
    if (current == null ||
        p.score > current.score ||
        (p.score == current.score && p.playedAt.isBefore(current.playedAt))) {
      mine[p.routineId] = p;
    }
  }

  final totals =
      [
        for (final MapEntry(:key, :value) in best.entries)
          (
            name: key,
            score: value.values.fold(0, (sum, p) => sum + p.score),
            reachedAt: value.values
                .map((p) => p.playedAt)
                .reduce((a, b) => a.isAfter(b) ? a : b),
          ),
      ]..sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        if (byScore != 0) return byScore;
        final byTime = a.reachedAt.compareTo(b.reachedAt);
        return byTime != 0 ? byTime : a.name.compareTo(b.name);
      });

  final myName = me == null ? null : _name(me);
  final rows = <LeaderboardRow>[];
  var rank = 0;
  for (var i = 0; i < totals.length; i++) {
    if (i == 0 || totals[i].score != totals[i - 1].score) rank = i + 1;
    rows.add(
      LeaderboardRow(
        rank: rank,
        displayName: totals[i].name,
        score: totals[i].score,
        isMe: totals[i].name == myName,
      ),
    );
  }

  final max = limit.clamp(1, 100);
  if (rows.length <= max) return rows;
  final top = rows.take(max).toList();
  final mine = rows.skip(max).where((r) => r.isMe);
  return [...top, ...mine];
}

DateTime _weekStart(DateTime now) {
  final utc = now.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day - (utc.weekday - 1));
}

String _name(String raw) => localPlayerKey(raw);

/// How a stored player name is told apart and shown: trimmed, blank = Player.
String localPlayerKey(String raw) {
  final t = raw.trim();
  return t.isEmpty ? 'Player' : t;
}

/// WM_OFFLINE leaderboard over the plays that `OfflineSessionsRepository`
/// stored on this device.
class OfflineLeaderboardRepository implements LeaderboardRepository {
  OfflineLeaderboardRepository(
    this._prefs, {
    required this.playerName,
    required this.routineIdsIn,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final SharedPreferences _prefs;
  final String? Function() playerName;

  /// Ids of the routines of a category (the content is not known here).
  final Future<Set<String>> Function(String category) routineIdsIn;
  final DateTime Function() _now;

  @override
  Future<List<LeaderboardRow>> fetch({
    String? routineId,
    required LeaderboardPeriod period,
    int limit = 50,
    String? category,
  }) async => computeLocalLeaderboard(
    readLocalPlays(_prefs),
    routineId: routineId,
    routineIds: category == null ? null : await routineIdsIn(category),
    period: period,
    limit: limit,
    me: playerName(),
    now: _now(),
  );
}
