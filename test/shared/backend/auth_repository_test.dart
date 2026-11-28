import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wiggle_move/shared/backend/auth_repository.dart';
import 'package:wiggle_move/shared/backend/offline_auth_repository.dart';

void main() {
  group('mapAuthException', () {
    String msg(Object e) => mapAuthException(e).message;

    test('invalid credentials', () {
      expect(
        msg(
          const AuthApiException(
            'Invalid login credentials',
            statusCode: '400',
            code: 'invalid_credentials',
          ),
        ),
        AuthFailure.invalidCredentials,
      );
    });

    test('user already exists (both codes)', () {
      for (final code in ['user_already_exists', 'email_exists']) {
        expect(
          msg(AuthApiException('raw', statusCode: '422', code: code)),
          AuthFailure.userExists,
        );
      }
    });

    test('weak password', () {
      expect(
        msg(
          AuthWeakPasswordException(
            message: 'raw',
            statusCode: '422',
            reasons: const ['length'],
          ),
        ),
        AuthFailure.weakPassword,
      );
    });

    test('email not confirmed', () {
      expect(
        msg(
          const AuthApiException(
            'raw',
            statusCode: '400',
            code: 'email_not_confirmed',
          ),
        ),
        AuthFailure.emailNotConfirmed,
      );
    });

    test('network failure', () {
      expect(
        msg(AuthRetryableFetchException(message: 'SocketException: boom')),
        AuthFailure.network,
      );
    });

    test('rate limit by code or 429 status', () {
      for (final code in [
        'over_request_rate_limit',
        'over_email_send_rate_limit',
      ]) {
        expect(
          msg(AuthApiException('raw', statusCode: '429', code: code)),
          AuthFailure.rateLimited,
        );
      }
      expect(
        msg(const AuthApiException('raw', statusCode: '429')),
        AuthFailure.rateLimited,
      );
    });

    test('unknown errors never leak raw server text', () {
      const raw = 'Database error saving new user: stack trace here';
      final m = msg(const AuthApiException(raw, statusCode: '500'));
      expect(m, AuthFailure.generic);
      expect(msg(StateError(raw)), AuthFailure.generic);
    });

    test('an AuthFailure passes through unchanged', () {
      const f = AuthFailure('custom');
      expect(mapAuthException(f), same(f));
    });
  });

  group('OfflineAuthRepository', () {
    Future<OfflineAuthRepository> repo([
      Map<String, Object> values = const {},
    ]) async {
      SharedPreferences.setMockInitialValues(values);
      return OfflineAuthRepository(await SharedPreferences.getInstance());
    }

    test('starts signed out with empty prefs', () async {
      expect((await repo()).currentUser, isNull);
    });

    test('restores a stored name', () async {
      final r = await repo({'player_name': 'Ann'});
      expect(r.currentUser?.displayName, 'Ann');
    });

    test('signUp signs in with the display name and persists it', () async {
      final r = await repo();
      final events = <AppUser?>[];
      final sub = r.authChanges.listen(events.add);
      await r.signUp(
        email: 'ann@x.com',
        password: 'secret12',
        displayName: 'Ann',
      );
      await pumpEventQueue();
      expect(r.currentUser?.displayName, 'Ann');
      expect(r.currentUser?.email, 'ann@x.com');
      expect(events.single?.displayName, 'Ann');
      final reloaded = OfflineAuthRepository(
        await SharedPreferences.getInstance(),
      );
      expect(reloaded.currentUser?.displayName, 'Ann');
      await sub.cancel();
    });

    test('signIn uses the email local part as name', () async {
      final r = await repo();
      await r.signIn(email: 'bo@x.com', password: 'whatever');
      expect(r.currentUser?.displayName, 'bo');
    });

    test('signOut clears the user and emits null', () async {
      final r = await repo({'player_name': 'Ann'});
      final events = <AppUser?>[];
      final sub = r.authChanges.listen(events.add);
      await r.signOut();
      await pumpEventQueue();
      expect(r.currentUser, isNull);
      expect(events, [null]);
      expect(
        OfflineAuthRepository(await SharedPreferences.getInstance())
            .currentUser,
        isNull,
      );
      await sub.cancel();
    });

    test('sendPasswordReset completes', () async {
      await (await repo()).sendPasswordReset('ann@x.com');
    });
  });
}
