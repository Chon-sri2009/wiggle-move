import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'sessions_repository.dart';

/// SharedPreferences key of the on-device leaderboard (read by
/// `features/leaderboard/leaderboard_store.dart`). Same key and entry shape
/// the pre-repository app used, so existing dev installs keep their scores.
const localLeaderboardKey = 'leaderboard_entries';

/// On-device sessions for `--dart-define=WM_OFFLINE=true`: each play is
/// appended to the local leaderboard under [playerName]'s current value
/// (skipped when there is no name). Always reports saved.
class OfflineSessionsRepository implements SessionsRepository {
  OfflineSessionsRepository(this._prefs, {required this.playerName});

  final SharedPreferences _prefs;
  final String? Function() playerName;

  @override
  Future<SubmitOutcome> submit(SessionSubmission submission) async {
    final name = playerName();
    if (name == null) return const SubmitSaved();
    var list = <Object?>[];
    final raw = _prefs.getString(localLeaderboardKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) list = decoded;
      } on FormatException {
        // Corrupt local leaderboard: start over.
      }
    }
    list.add({
      'playerName': name,
      'routineId': submission.routineId,
      'score': submission.score,
      'playedAt': submission.playedAt.toIso8601String(),
    });
    await _prefs.setString(localLeaderboardKey, jsonEncode(list));
    return const SubmitSaved();
  }
}
