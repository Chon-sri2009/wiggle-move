import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wiggle_move/shared/legacy_data_migration.dart';

Future<SharedPreferences> _prefs(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

const _old = <String, Object>{
  'player_name': 'Ann',
  'player_email': 'a@x.com',
  'onboarded': true,
  'profile_goals': ['Burn Calories'],
  'profile_styles': ['Cardio'],
  'profile_level': 'Beginner',
  'leaderboard_entries': '[{"playerName":"Ann"}]',
};

void main() {
  test('online: clears old local data once and records the version', () async {
    final p = await _prefs({
      ..._old,
      'pending_submissions': 'keep',
      'unrelated': 'keep',
    });
    await migrateLegacyData(p, offline: false);
    for (final k in legacyLocalKeys) {
      expect(p.containsKey(k), isFalse, reason: k);
    }
    expect(p.getInt(migrationVersionKey), 1);
    expect(p.getString('pending_submissions'), 'keep');
    expect(p.getString('unrelated'), 'keep');
  });

  test('second run is a no-op even if the keys came back', () async {
    final p = await _prefs({});
    await migrateLegacyData(p, offline: false);
    await p.setString('player_name', 'New');
    await migrateLegacyData(p, offline: false);
    expect(p.getString('player_name'), 'New');
  });

  test('offline: live local data is untouched and not recorded', () async {
    final p = await _prefs(_old);
    await migrateLegacyData(p, offline: true);
    for (final k in legacyLocalKeys) {
      expect(p.containsKey(k), isTrue, reason: k);
    }
    expect(p.containsKey(migrationVersionKey), isFalse);
    // Going online later still cleans up.
    await migrateLegacyData(p, offline: false);
    expect(p.containsKey('player_name'), isFalse);
  });

  test('wrong-typed keys and a corrupt version do not throw', () async {
    final p = await _prefs({
      'player_name': 5,
      'leaderboard_entries': 42,
      'onboarded': 'yes',
      migrationVersionKey: 'garbage',
    });
    await migrateLegacyData(p, offline: false);
    expect(p.containsKey('player_name'), isFalse);
    expect(p.containsKey('leaderboard_entries'), isFalse);
    expect(p.getInt(migrationVersionKey), 1);
  });

  test('empty prefs just records the version', () async {
    final p = await _prefs({});
    await migrateLegacyData(p, offline: false);
    expect(p.getInt(migrationVersionKey), 1);
  });
}
