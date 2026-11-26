import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'sessions_repository.dart';

/// SharedPreferences key of the plays stored on this device under
/// WM_OFFLINE (read by `OfflineLeaderboardRepository`). Same key and entry
/// shape the pre-repository app used, so existing dev installs keep their
/// scores.
const localLeaderboardKey = 'leaderboard_entries';

/// One play stored on this device (WM_OFFLINE).
class LocalPlay {
  const LocalPlay({
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

  static LocalPlay? tryFromJson(Object? json) {
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
    return LocalPlay(
      playerName: name,
      routineId: routine,
      score: score,
      playedAt: date,
    );
  }
}

/// The raw stored list under [localLeaderboardKey]; empty when missing,
/// corrupt or of the wrong type. Never throws.
List<Object?> readLocalPlayList(SharedPreferences prefs) {
  final raw = prefs.get(localLeaderboardKey);
  if (raw is! String) return [];
  try {
    final decoded = jsonDecode(raw);
    return decoded is List ? decoded : [];
  } on FormatException {
    return [];
  }
}

/// The valid plays stored on this device (malformed entries are skipped).
List<LocalPlay> readLocalPlays(SharedPreferences prefs) =>
    readLocalPlayList(prefs)
        .map(LocalPlay.tryFromJson)
        .whereType<LocalPlay>()
        .toList();

/// On-device sessions for `--dart-define=WM_OFFLINE=true`: each play is
/// appended to the local plays under [playerName]'s current value (skipped
/// when there is no name). Always reports saved.
class OfflineSessionsRepository implements SessionsRepository {
  OfflineSessionsRepository(this._prefs, {required this.playerName});

  final SharedPreferences _prefs;
  final String? Function() playerName;

  @override
  Future<SubmitOutcome> submit(SessionSubmission submission) async {
    final name = playerName();
    if (name == null) return const SubmitSaved();
    final list = readLocalPlayList(_prefs)
      ..add(
        LocalPlay(
          playerName: name,
          routineId: submission.routineId,
          score: submission.score,
          playedAt: submission.playedAt,
        ).toJson(),
      );
    await _prefs.setString(localLeaderboardKey, jsonEncode(list));
    return const SubmitSaved();
  }
}
