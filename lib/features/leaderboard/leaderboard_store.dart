import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/backend/offline_sessions_repository.dart';
import '../../shared/backend/sessions_providers.dart';
import '../../shared/prefs.dart';

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

/// Plays stored on this device. Written by `OfflineSessionsRepository`
/// (WM_OFFLINE) through the sessions repository; reloaded whenever a play's
/// upload status changes. Server-backed leaderboard: WM-24.
class LeaderboardNotifier extends Notifier<List<LeaderboardEntry>> {
  @override
  List<LeaderboardEntry> build() {
    ref.watch(submissionStatusProvider);
    final raw = ref.read(sharedPrefsProvider).getString(localLeaderboardKey);
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
