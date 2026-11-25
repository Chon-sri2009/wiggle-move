import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wiggle_move/shared/backend/offline_profile_repository.dart';
import 'package:wiggle_move/shared/backend/profile.dart';
import 'package:wiggle_move/shared/backend/profile_repository.dart';

void main() {
  group('mapRepositoryException', () {
    String msg(Object e) => mapRepositoryException(e).message;

    test('passes RepositoryFailure through', () {
      expect(msg(const RepositoryFailure('kept')), 'kept');
    });

    test('network errors', () {
      expect(msg(const SocketException('raw')), RepositoryFailure.network);
      expect(msg(TimeoutException('raw')), RepositoryFailure.network);
    });

    test('expired JWT or auth error means sign in again', () {
      expect(
        msg(const PostgrestException(message: 'JWT expired', code: 'PGRST301')),
        RepositoryFailure.sessionExpired,
      );
      expect(msg(const AuthException('raw')), RepositoryFailure.sessionExpired);
    });

    test('other server errors never leak raw text', () {
      final f = mapRepositoryException(
        const PostgrestException(message: 'secret detail', code: '42501'),
      );
      expect(f.message, RepositoryFailure.generic);
      expect(msg(StateError('boom')), RepositoryFailure.generic);
    });
  });

  group('Profile rows', () {
    test('fromRow reads Postgres arrays and nulls', () {
      final p = Profile.fromRow({
        'goals': <dynamic>['Burn Calories'],
        'styles': <dynamic>['Cardio', 'Bodyweight'],
        'level': 'Beginner',
        'onboarded': true,
      });
      expect(
        p,
        const Profile(
          goals: ['Burn Calories'],
          styles: ['Cardio', 'Bodyweight'],
          level: 'Beginner',
          onboarded: true,
        ),
      );
      expect(Profile.fromRow({}), const Profile());
    });

    test('toRow writes only UPDATE-granted columns', () {
      final row = const Profile(
        goals: ['a'],
        styles: ['b'],
        level: 'Advanced',
        onboarded: true,
      ).toRow();
      expect(row, {
        'goals': ['a'],
        'styles': ['b'],
        'level': 'Advanced',
        'onboarded': true,
      });
    });
  });

  group('OfflineProfileRepository', () {
    test('defaults to not onboarded', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = OfflineProfileRepository(
        await SharedPreferences.getInstance(),
      );
      expect(await repo.load(), const Profile());
    });

    test('save then load round-trips with the existing keys', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = OfflineProfileRepository(prefs);
      const p = Profile(
        goals: ['Stay Healthy'],
        styles: ['Stretching'],
        level: 'Intermediate',
        onboarded: true,
      );
      await repo.save(p);
      expect(await repo.load(), p);
      expect(prefs.getBool('onboarded'), isTrue);
      expect(prefs.getStringList('profile_goals'), ['Stay Healthy']);
    });

    test('reads data written by the pre-repository app', () async {
      SharedPreferences.setMockInitialValues({
        'onboarded': true,
        'profile_level': 'Beginner',
      });
      final repo = OfflineProfileRepository(
        await SharedPreferences.getInstance(),
      );
      final p = await repo.load();
      expect(p.onboarded, isTrue);
      expect(p.level, 'Beginner');
    });
  });
}
