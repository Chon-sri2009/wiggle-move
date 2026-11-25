import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wiggle_move/app/app.dart';
import 'package:wiggle_move/features/leaderboard/leaderboard_store.dart';
import 'package:wiggle_move/shared/backend/auth_providers.dart';
import 'package:wiggle_move/shared/backend/auth_repository.dart';

import '../support/fakes.dart';

Future<Widget> _app(FakeAuthRepository auth, {bool onboarded = false}) async {
  SharedPreferences.setMockInitialValues({'onboarded': onboarded});
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      authRepositoryProvider.overrideWithValue(auth),
    ],
    child: const WiggleMoveApp(),
  );
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
}
