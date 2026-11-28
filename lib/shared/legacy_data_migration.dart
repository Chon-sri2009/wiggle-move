import 'package:shared_preferences/shared_preferences.dart';

/// Keys written by the pre-backend, device-only app (and still written by
/// the WM_OFFLINE repositories): local name/email, local profile answers and
/// the local leaderboard plays. Online they are never read: identity,
/// profile and scores live on the server.
const legacyLocalKeys = [
  'player_name',
  'player_email',
  'onboarded',
  'profile_goals',
  'profile_styles',
  'profile_level',
  'profile_avatar',
  'leaderboard_entries',
];

/// SharedPreferences key holding the number of migrations already applied.
const migrationVersionKey = 'migrations_v';

const _currentVersion = 1;

/// One-time cleanup of data from earlier app versions.
///
/// Under WM_OFFLINE ([offline]) the legacy keys are live data, so nothing is
/// touched and nothing is recorded (a later online run still cleans up).
/// Online, the keys are removed once and the version is recorded; later runs
/// do nothing. Wrong-typed or corrupt values are removed like any other, and
/// this never throws.
Future<void> migrateLegacyData(
  SharedPreferences prefs, {
  required bool offline,
}) async {
  if (offline) return;
  try {
    final done = prefs.get(migrationVersionKey);
    if (done is int && done >= _currentVersion) return;
    for (final key in legacyLocalKeys) {
      await prefs.remove(key);
    }
    await prefs.setInt(migrationVersionKey, _currentVersion);
  } catch (_) {
    // Best effort: the keys are unused online, and the next start retries.
  }
}
