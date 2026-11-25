import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wiggle_move/app/app.dart';
import 'package:wiggle_move/features/leaderboard/leaderboard_store.dart';
import 'package:wiggle_move/shared/backend/auth_providers.dart';
import 'package:wiggle_move/shared/backend/offline_auth_repository.dart';

Future<Widget> _app([Map<String, Object> prefs = const {}]) async {
  SharedPreferences.setMockInitialValues(prefs);
  final instance = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(instance),
      // The WM_OFFLINE implementation: exercises the local end-to-end path.
      authRepositoryProvider.overrideWithValue(OfflineAuthRepository(instance)),
    ],
    child: const WiggleMoveApp(),
  );
}

const _signedIn = {'player_name': 'Ann', 'onboarded': true};

void main() {
  testWidgets('signed-out user lands on login and can switch to sign up', (
    tester,
  ) async {
    await tester.pumpWidget(await _app());
    await tester.pumpAndSettle();
    expect(find.text('Continue with Google'), findsOneWidget);

    await tester.tap(find.text('Sign up'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Sign up'), findsOneWidget);
    expect(find.text('Name'), findsOneWidget);
  });

  testWidgets('login validates then continues to personalization', (
    tester,
  ) async {
    await tester.pumpWidget(await _app());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Login'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'ann@x.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'secret12',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Login'));
    await tester.pumpAndSettle();
    expect(find.text('Personalization'), findsOneWidget);
  });

  testWidgets('offline sign up -> personalize -> home', (tester) async {
    await tester.pumpWidget(await _app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign up'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Cy');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'cy@x.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'secret12',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Sign up'));
    await tester.pumpAndSettle();
    expect(find.text('Personalization'), findsOneWidget);

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
    expect(find.text('Hi, Cy'), findsOneWidget);
  });

  testWidgets('personalization flow ends on home', (tester) async {
    await tester.pumpWidget(await _app({'player_name': 'Ann'}));
    await tester.pumpAndSettle();
    expect(find.text('Personalization'), findsOneWidget);

    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(find.text('Your Fitness Goal'), findsOneWidget);
    // Next is disabled until something is picked.
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Next'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Burn Calories'));
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('Workout Style'), findsOneWidget);
    await tester.tap(find.text('Cardio'));
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('Experience Level'), findsOneWidget);
    await tester.tap(find.text('Beginner'));
    await tester.pump();
    await tester.tap(find.text('Create My Workout Plan'));
    await tester.pumpAndSettle();

    expect(find.text('Hi, Ann'), findsOneWidget);
    expect(find.text('Coach Mia'), findsOneWidget);
  });

  testWidgets('home lists trainers and opens their routines', (tester) async {
    await tester.pumpWidget(await _app(_signedIn));
    await tester.pumpAndSettle();
    expect(find.text('Coach Mia'), findsOneWidget);
    expect(find.text('Coach Jay'), findsOneWidget);

    await tester.tap(find.text('Coach Mia'));
    await tester.pumpAndSettle();
    expect(find.text('Pop Starter'), findsOneWidget);
    expect(find.text('Disco Fever'), findsOneWidget);
  });

  testWidgets('leaderboard shows empty state', (tester) async {
    await tester.pumpWidget(await _app(_signedIn));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Leaderboard'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No scores yet'), findsOneWidget);
  });

  testWidgets('sign out returns to login', (tester) async {
    await tester.pumpWidget(await _app(_signedIn));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Continue with Google'), findsOneWidget);
  });

  test('rankEntries keeps best score per player and sorts descending', () {
    LeaderboardEntry e(String n, int s, [String r = 'a']) => LeaderboardEntry(
      playerName: n,
      routineId: r,
      score: s,
      playedAt: DateTime(2026),
    );
    final ranked = rankEntries([
      e('Ann', 60),
      e('Ann', 80),
      e('Bo', 70),
      e('Bo', 90, 'b'),
    ], routineId: 'a');
    expect(ranked.map((x) => '${x.playerName}:${x.score}'), [
      'Ann:80',
      'Bo:70',
    ]);
  });
}
