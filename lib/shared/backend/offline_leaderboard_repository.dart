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

/// Sample community players for WM_OFFLINE so the leaderboard feels alive and
/// gives the user realistic targets to beat across every category and routine.
List<LocalPlay> demoLeaderboardPlays(DateTime now) {
  final utc = now.toUtc();
  final weekStart = _weekStart(utc);
  // Keep every timestamp within [weekStart, utc] so weekly & all-time both show.
  DateTime at(int minutesAfterMonday) {
    final t = weekStart.add(Duration(minutes: minutesAfterMonday));
    return t.isAfter(utc) ? utc.subtract(const Duration(minutes: 1)) : t;
  }

  const players = <(String, Map<String, int>)>[
    (
      'Ploy',
      {
        'video-squat-demo': 96,
        'squat-sets': 94,
        'cardio-burn': 92,
        'pop-starter': 95,
        'disco-fever': 91,
        'cardio-circuit': 90,
      },
    ),
    (
      'Bank',
      {
        'video-squat-demo': 93,
        'squat-sets': 95,
        'cardio-circuit': 92,
        'cardio-burn': 89,
        'pop-starter': 88,
      },
    ),
    (
      'Mint',
      {
        'video-squat-demo': 91,
        'pop-starter': 94,
        'disco-fever': 93,
        'cardio-burn': 87,
        'squat-sets': 86,
      },
    ),
    (
      'Tae',
      {
        'video-squat-demo': 88,
        'squat-sets': 90,
        'cardio-circuit': 87,
        'video-workout-30': 85,
        'disco-fever': 84,
      },
    ),
    (
      'Fah',
      {
        'video-squat-demo': 85,
        'pop-starter': 91,
        'cardio-burn': 84,
        'squat-sets': 82,
      },
    ),
    (
      'Khao',
      {
        'video-squat-demo': 82,
        'disco-fever': 88,
        'cardio-circuit': 81,
        'squat-sets': 80,
      },
    ),
    (
      'Beam',
      {
        'video-squat-demo': 79,
        'cardio-burn': 83,
        'pop-starter': 81,
        'squat-sets': 78,
      },
    ),
    (
      'NongPim',
      {
        'video-squat-demo': 76,
        'pop-starter': 79,
        'disco-fever': 75,
        'cardio-burn': 74,
      },
    ),
    ('Ken', {'video-squat-demo': 72, 'squat-sets': 75, 'cardio-circuit': 71}),
    ('Grace', {'video-squat-demo': 68, 'pop-starter': 74, 'cardio-burn': 69}),
  ];

  final out = <LocalPlay>[];
  var offset = 10;
  for (final (name, scores) in players) {
    for (final entry in scores.entries) {
      out.add(
        LocalPlay(
          playerName: name,
          routineId: entry.key,
          score: entry.value,
          playedAt: at(offset),
        ),
      );
      offset += 7;
    }
  }
  return out;
}

/// WM_OFFLINE leaderboard over the plays that `OfflineSessionsRepository`
/// stored on this device.
class OfflineLeaderboardRepository implements LeaderboardRepository {
  OfflineLeaderboardRepository(
    this._prefs, {
    required this.playerName,
    required this.routineIdsIn,
    this.includeDemoPlayers = false,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final SharedPreferences _prefs;
  final String? Function() playerName;

  /// Ids of the routines of a category (the content is not known here).
  final Future<Set<String>> Function(String category) routineIdsIn;
  final bool includeDemoPlayers;
  final DateTime Function() _now;

  @override
  Future<List<LeaderboardRow>> fetch({
    String? routineId,
    required LeaderboardPeriod period,
    int limit = 50,
    String? category,
  }) async {
    final now = _now();
    final plays = [
      if (includeDemoPlayers) ...demoLeaderboardPlays(now),
      ...readLocalPlays(_prefs),
    ];
    return computeLocalLeaderboard(
      plays,
      routineId: routineId,
      routineIds: category == null ? null : await routineIdsIn(category),
      period: period,
      limit: limit,
      me: playerName(),
      now: now,
    );
  }
}
