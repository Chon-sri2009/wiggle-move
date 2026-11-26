import 'package:shared_preferences/shared_preferences.dart';

import 'history_repository.dart';
import 'offline_leaderboard_repository.dart' show localPlayerKey;
import 'offline_sessions_repository.dart';

/// WM_OFFLINE history: the plays this device stored for the signed-in
/// player, newest first. Only totals are kept offline, so [HistoryEntry.results]
/// is empty.
class OfflineHistoryRepository implements HistoryRepository {
  OfflineHistoryRepository(this._prefs, {required this.playerName});

  final SharedPreferences _prefs;
  final String? Function() playerName;

  @override
  Future<List<HistoryEntry>> fetch({int limit = 50}) async {
    final me = playerName()?.trim();
    if (me == null || me.isEmpty) return const [];
    final mine =
        readLocalPlays(_prefs)
            .where((p) => localPlayerKey(p.playerName) == localPlayerKey(me))
            .toList()
          ..sort((a, b) => b.playedAt.compareTo(a.playedAt));
    return [
      for (final (i, p) in mine.take(limit.clamp(1, 100)).indexed)
        HistoryEntry(
          id: 'local-$i',
          routineId: p.routineId,
          score: p.score,
          durationMs: 0,
          playedAt: p.playedAt,
          results: const [],
        ),
    ];
  }
}
