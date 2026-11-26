import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wiggle_move/app/app.dart';
import 'package:wiggle_move/shared/prefs.dart';
import 'package:wiggle_move/shared/backend/auth_providers.dart';
import 'package:wiggle_move/shared/backend/auth_repository.dart';
import 'package:wiggle_move/shared/backend/content_providers.dart';
import 'package:wiggle_move/shared/backend/profile.dart';
import 'package:wiggle_move/shared/backend/profile_providers.dart';
import 'package:wiggle_move/shared/backend/profile_repository.dart';

import '../support/fakes.dart';

Future<Widget> _app(
  FakeAuthRepository auth, {
  bool onboarded = false,
  FakeProfileRepository? profiles,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final repo =
      profiles ??
      FakeProfileRepository(auth, {
        if (onboarded) 'u1': FakeProfileRepository.onboarded,
      });
  return ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      authRepositoryProvider.overrideWithValue(auth),
      profileRepositoryProvider.overrideWithValue(repo),
      contentRepositoryProvider.overrideWithValue(FakeContentRepository()),
    ],
    child: const WiggleMoveApp(),
  );
}

Future<void> _personalize(WidgetTester tester) async {
  await tester.tap(find.text('Start'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Burn Calories'));
  await tester.pump();
  await tester.tap(find.text('Next'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Cardio'));
  await tester.pump();
  await tester.tap(find.text('Next'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Beginner'));
  await tester.pump();
  await tester.tap(find.text('Create My Workout Plan'));
  await tester.pumpAndSettle();
}

Future<void> _fillLogin(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Email'),
    'ann@x.com',
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Password'),
    'secret12',
  );
}

void main() {
  testWidgets('signed out -> /login', (tester) async {
    await tester.pumpWidget(await _app(FakeAuthRepository()));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Login'), findsOneWidget);
  });

  testWidgets('signed in, not onboarded -> /personalize', (tester) async {
    final auth = FakeAuthRepository(FakeAuthRepository.ann);
    await tester.pumpWidget(await _app(auth));
    await tester.pumpAndSettle();
    expect(find.text('Personalization'), findsOneWidget);
  });

  testWidgets('signed in, onboarded -> / with the display name', (
    tester,
  ) async {
    final auth = FakeAuthRepository(FakeAuthRepository.ann);
    await tester.pumpWidget(await _app(auth, onboarded: true));
    await tester.pumpAndSettle();
    expect(find.text('Hi, Ann'), findsOneWidget);
  });

  testWidgets('login moves on when the auth stream reports a user', (
    tester,
  ) async {
    final auth = FakeAuthRepository();
    await tester.pumpWidget(await _app(auth, onboarded: true));
    await tester.pumpAndSettle();
    await _fillLogin(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Login'));
    await tester.pumpAndSettle();
    expect(find.text('Hi, ann'), findsOneWidget);
  });

  testWidgets('sign-out returns to /login', (tester) async {
    final auth = FakeAuthRepository(FakeAuthRepository.ann);
    await tester.pumpWidget(await _app(auth, onboarded: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Profile'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Sign out'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(auth.currentUser, isNull);
    expect(find.widgetWithText(FilledButton, 'Login'), findsOneWidget);
  });

  testWidgets('login failure shows the mapped message and stays', (
    tester,
  ) async {
    final auth = FakeAuthRepository()
      ..failWith = const AuthFailure(AuthFailure.invalidCredentials);
    await tester.pumpWidget(await _app(auth));
    await tester.pumpAndSettle();
    await _fillLogin(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Login'));
    await tester.pumpAndSettle();
    expect(find.text(AuthFailure.invalidCredentials), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Login'), findsOneWidget);
  });

  testWidgets('short password is rejected before calling the backend', (
    tester,
  ) async {
    final auth = FakeAuthRepository();
    await tester.pumpWidget(await _app(auth));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'ann@x.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'short',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Login'));
    await tester.pumpAndSettle();
    expect(find.text('At least 8 characters'), findsOneWidget);
    expect(auth.currentUser, isNull);
  });

  testWidgets('forgot password sends a reset with a neutral message', (
    tester,
  ) async {
    final auth = FakeAuthRepository();
    await tester.pumpWidget(await _app(auth));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'ann@x.com',
    );
    await tester.tap(find.text('Forgot your password?'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Send link'));
    await tester.pumpAndSettle();
    expect(auth.resetRequests, ['ann@x.com']);
    expect(find.textContaining('If an account exists'), findsOneWidget);
  });

  testWidgets('a failed reset shows its error inside the dialog', (
    tester,
  ) async {
    final auth = FakeAuthRepository()
      ..failWith = const AuthFailure(AuthFailure.network);
    await tester.pumpWidget(await _app(auth));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'ann@x.com',
    );
    await tester.tap(find.text('Forgot your password?'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Send link'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(AuthFailure.network),
      ),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);
  });

  group('server profile (WM-21)', () {
    testWidgets('onboarded on the server skips personalization', (
      tester,
    ) async {
      final auth = FakeAuthRepository(FakeAuthRepository.ann);
      await tester.pumpWidget(await _app(auth, onboarded: true));
      await tester.pumpAndSettle();
      expect(find.text('Hi, Ann'), findsOneWidget);
      expect(find.text('Personalization'), findsNothing);
    });

    testWidgets('while the profile loads it shows a spinner, not personalize', (
      tester,
    ) async {
      final auth = FakeAuthRepository(FakeAuthRepository.ann);
      final repo = FakeProfileRepository(auth, {
        'u1': FakeProfileRepository.onboarded,
      })..loadGate = Completer();
      await tester.pumpWidget(await _app(auth, profiles: repo));
      await tester.pump();
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Personalization'), findsNothing);
      expect(find.text('Hi, Ann'), findsNothing);

      repo.loadGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Hi, Ann'), findsOneWidget);
    });

    testWidgets('load failure shows the message and retry recovers', (
      tester,
    ) async {
      final auth = FakeAuthRepository(FakeAuthRepository.ann);
      final repo = FakeProfileRepository(auth, {
        'u1': FakeProfileRepository.onboarded,
      })..failLoad = const RepositoryFailure(RepositoryFailure.network);
      await tester.pumpWidget(await _app(auth, profiles: repo));
      await tester.pumpAndSettle();
      expect(find.text(RepositoryFailure.network), findsOneWidget);
      expect(find.text('Personalization'), findsNothing);

      repo.failLoad = null;
      await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Hi, Ann'), findsOneWidget);
    });

    testWidgets('completing personalization saves to the repository', (
      tester,
    ) async {
      final auth = FakeAuthRepository(FakeAuthRepository.ann);
      final repo = FakeProfileRepository(auth);
      await tester.pumpWidget(await _app(auth, profiles: repo));
      await tester.pumpAndSettle();
      await _personalize(tester);
      expect(find.text('Hi, Ann'), findsOneWidget);
      expect(
        repo.profiles['u1'],
        const Profile(
          goals: ['Burn Calories'],
          styles: ['Cardio'],
          level: 'Beginner',
          onboarded: true,
        ),
      );
    });

    testWidgets('save failure keeps the user on the step with an error', (
      tester,
    ) async {
      final auth = FakeAuthRepository(FakeAuthRepository.ann);
      final repo = FakeProfileRepository(auth)
        ..failSave = const RepositoryFailure(RepositoryFailure.network);
      await tester.pumpWidget(await _app(auth, profiles: repo));
      await tester.pumpAndSettle();
      await _personalize(tester);
      expect(find.text(RepositoryFailure.network), findsOneWidget);
      expect(find.text('Experience Level'), findsOneWidget);
      expect(find.text('Hi, Ann'), findsNothing);
      expect(repo.profiles, isEmpty);
    });

    testWidgets('a different user does not inherit the previous profile', (
      tester,
    ) async {
      final auth = FakeAuthRepository(FakeAuthRepository.ann);
      final repo = FakeProfileRepository(auth, {
        'u1': FakeProfileRepository.onboarded,
      });
      await tester.pumpWidget(await _app(auth, profiles: repo));
      await tester.pumpAndSettle();
      expect(find.text('Hi, Ann'), findsOneWidget);

      auth.emit(null);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Login'), findsOneWidget);

      // Bob's load is held: nothing of Ann's may be shown meanwhile.
      repo.loadGate = Completer();
      auth.emit(
        const AppUser(id: 'u2', email: 'bob@x.com', displayName: 'Bob'),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Hi, Bob'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      repo.loadGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Personalization'), findsOneWidget);
    });
  });
}
