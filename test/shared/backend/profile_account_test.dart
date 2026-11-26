import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show FunctionsFetchException;
import 'package:wiggle_move/shared/backend/auth_repository.dart';
import 'package:wiggle_move/shared/backend/offline_auth_repository.dart';
import 'package:wiggle_move/shared/backend/offline_profile_repository.dart';
import 'package:wiggle_move/shared/backend/offline_sessions_repository.dart';
import 'package:wiggle_move/shared/backend/profile.dart';

Future<SharedPreferences> _prefs([Map<String, Object> v = const {}]) async {
  SharedPreferences.setMockInitialValues(v);
  return SharedPreferences.getInstance();
}

void main() {
  group('Profile avatar', () {
    test('is read from the row and written back', () {
      final p = Profile.fromRow({
        'goals': ['Cardio'],
        'styles': <String>[],
        'level': 'Beginner',
        'avatar': '🐰',
        'onboarded': true,
      });
      expect(p.avatar, '🐰');
      expect(p.toRow()['avatar'], '🐰');
      expect(Profile.fromRow({'avatar': null}).avatar, isNull);
    });

    test('takes part in equality', () {
      expect(const Profile(avatar: 'a'), isNot(const Profile(avatar: 'b')));
      expect(const Profile(avatar: 'a'), const Profile(avatar: 'a'));
    });
  });

  group('OfflineProfileRepository', () {
    test('round-trips the avatar and clears it with null', () async {
      final repo = OfflineProfileRepository(await _prefs());
      await repo.save(const Profile(avatar: '🦊', onboarded: true));
      expect((await repo.load()).avatar, '🦊');
      await repo.save(const Profile(onboarded: true));
      expect((await repo.load()).avatar, isNull);
    });

    test('saveDisplayName changes nothing (the name is the account)', () async {
      final prefs = await _prefs({'profile_level': 'Beginner'});
      await OfflineProfileRepository(prefs).saveDisplayName('Ann');
      expect(prefs.getKeys(), {'profile_level'});
    });
  });

  group('OfflineAuthRepository', () {
    test('updateDisplayName changes and announces the user', () async {
      final auth = OfflineAuthRepository(
        await _prefs({'player_name': 'Ann', 'player_email': 'a@x.com'}),
      );
      final seen = <AppUser?>[];
      auth.authChanges.listen(seen.add);
      await auth.updateDisplayName('Bo');
      await Future<void>.delayed(Duration.zero);
      expect(auth.currentUser?.displayName, 'Bo');
      expect(auth.currentUser?.email, 'a@x.com');
      expect(seen.single?.displayName, 'Bo');
    });

    test('deleteAccount clears the account, profile and plays', () async {
      final prefs = await _prefs({
        'player_name': 'Ann',
        'player_email': 'a@x.com',
        'onboarded': true,
        'profile_avatar': '🐰',
        localLeaderboardKey: '[]',
        'pending_submissions': 'keep',
      });
      final auth = OfflineAuthRepository(prefs);
      final seen = <AppUser?>[];
      auth.authChanges.listen(seen.add);
      await auth.deleteAccount();
      await Future<void>.delayed(Duration.zero);
      expect(auth.currentUser, isNull);
      expect(seen, [null]);
      expect(prefs.containsKey('profile_avatar'), isFalse);
      expect(prefs.containsKey(localLeaderboardKey), isFalse);
      expect(prefs.getString('pending_submissions'), 'keep');
    });
  });

  test('mapAuthException: connection problems are network failures', () {
    for (final e in <Object>[
      const SocketException('down'),
      TimeoutException('slow'),
      const FunctionsFetchException(details: 'x'),
    ]) {
      expect(mapAuthException(e).message, AuthFailure.network);
    }
  });
}
