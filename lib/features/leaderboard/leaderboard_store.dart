import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Overridden in `main()` once SharedPreferences has loaded.
final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(),
);

class LeaderboardEntry {
  const LeaderboardEntry({
    required this.playerName,
    required this.routineId,
    required this.score,
    required this.playedAt,
  });

  final String playerName;
  final String routineId;
  final int score;
  final DateTime playedAt;

  Map<String, Object> toJson() => {
    'playerName': playerName,
    'routineId': routineId,
    'score': score,
    'playedAt': playedAt.toIso8601String(),
  };

  static LeaderboardEntry? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['playerName'], routine = json['routineId'];
    final score = json['score'], at = json['playedAt'];
    if (name is! String ||
        routine is! String ||
        score is! int ||
        at is! String) {
      return null;
    }
    final date = DateTime.tryParse(at);
    if (date == null) return null;
    return LeaderboardEntry(
      playerName: name,
      routineId: routine,
      score: score,
      playedAt: date,
    );
  }
}

const _entriesKey = 'leaderboard_entries';

/// Stores played sessions on this device. Swap for Supabase to share a
/// leaderboard between users (see docs/PROJECT.md).
class LeaderboardNotifier extends Notifier<List<LeaderboardEntry>> {
  @override
  List<LeaderboardEntry> build() {
    final raw = ref.read(sharedPrefsProvider).getString(_entriesKey);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return list
          .map(LeaderboardEntry.tryFromJson)
          .whereType<LeaderboardEntry>()
          .toList();
    } on FormatException {
      return const [];
    }
  }

  Future<void> add(LeaderboardEntry entry) async {
    state = [...state, entry];
    await ref
        .read(sharedPrefsProvider)
        .setString(
          _entriesKey,
          jsonEncode(state.map((e) => e.toJson()).toList()),
        );
  }
}

final leaderboardProvider =
    NotifierProvider<LeaderboardNotifier, List<LeaderboardEntry>>(
      LeaderboardNotifier.new,
    );

/// Best score per player for [routineId] (all routines if null), highest first.
List<LeaderboardEntry> rankEntries(
  List<LeaderboardEntry> entries, {
  String? routineId,
}) {
  final best = <String, LeaderboardEntry>{};
  for (final e in entries) {
    if (routineId != null && e.routineId != routineId) continue;
    final key = '${e.playerName}|${e.routineId}';
    final current = best[key];
    if (current == null || e.score > current.score) best[key] = e;
  }
  return best.values.toList()..sort((a, b) => b.score.compareTo(a.score));
}
