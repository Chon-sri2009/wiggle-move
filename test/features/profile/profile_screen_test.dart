import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wiggle_move/features/profile/profile_loading_screen.dart';
import 'package:wiggle_move/features/profile/profile_screen.dart';
import 'package:wiggle_move/features/profile/profile_store.dart';
import 'package:wiggle_move/shared/backend/auth_providers.dart';
import 'package:wiggle_move/shared/backend/auth_repository.dart';
import 'package:wiggle_move/shared/backend/profile.dart';
import 'package:wiggle_move/shared/backend/profile_providers.dart';
import 'package:wiggle_move/shared/backend/profile_repository.dart';
import 'package:wiggle_move/shared/prefs.dart';

import '../../support/fakes.dart';

const _stored = Profile(
  goals: ['Burn Calories'],
  styles: ['Cardio'],
  level: 'Beginner',
  onboarded: true,
);

class _Env {
  _Env(this.auth, this.profiles, this.container);
  final FakeAuthRepository auth;
  final FakeProfileRepository profiles;
  final ProviderContainer container;
}

/// A tall screen, so the whole (lazily built) list is on screen.
void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<_Env> _pump(WidgetTester tester) async {
  _tall(tester);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final auth = FakeAuthRepository(FakeAuthRepository.ann);
  final profiles = FakeProfileRepository(auth, {'u1': _stored});
  final container = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      authRepositoryProvider.overrideWithValue(auth),
      profileRepositoryProvider.overrideWithValue(profiles),
    ],
  );
  addTearDown(container.dispose);
  await container.read(profileProvider.future);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ProfileScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return _Env(auth, profiles, container);
}

Finder _save() => find.widgetWithText(FilledButton, 'Save changes');

Future<void> _tapVisible(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

bool _selected(WidgetTester tester, String label) =>
    tester.widget<FilterChip>(find.widgetWithText(FilterChip, label)).selected;

void main() {
  testWidgets('shows the stored values and Save is disabled until a change', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.widgetWithText(TextFormField, 'Ann'), findsOneWidget);
    expect(_selected(tester, 'Cardio'), isTrue);
    expect(_selected(tester, 'Beginner'), isTrue);
    expect(_selected(tester, 'Advanced'), isFalse);
    expect(tester.widget<FilledButton>(_save()).onPressed, isNull);
  });

  testWidgets('saves edited answers and avatar to the profile', (tester) async {
    final env = await _pump(tester);
    await _tapVisible(
      tester,
      find.widgetWithText(FilterChip, 'Build Strength'),
    );
    await _tapVisible(tester, find.widgetWithText(FilterChip, 'Advanced'));
    await _tapVisible(tester, find.text('🦊'));
    await _tapVisible(tester, _save());

    expect(
      env.profiles.profiles['u1'],
      const Profile(
        goals: ['Burn Calories', 'Build Strength'],
        styles: ['Cardio'],
        level: 'Advanced',
        avatar: '🦊',
        onboarded: true,
      ),
    );
    expect(env.profiles.names, isEmpty);
    expect(find.text('Profile saved'), findsOneWidget);
    expect(tester.widget<FilledButton>(_save()).onPressed, isNull);
  });

  testWidgets('a renamed user updates the leaderboard name and the account', (
    tester,
  ) async {
    final env = await _pump(tester);
    await tester.enterText(find.byType(TextFormField), '  Annie ');
    await tester.pump();
    await _tapVisible(tester, _save());
    expect(env.profiles.names, ['Annie']);
    expect(env.auth.nameUpdates, ['Annie']);
    expect(env.profiles.profiles['u1'], _stored); // answers untouched
  });

  testWidgets('blank and over-long names are rejected', (tester) async {
    final env = await _pump(tester);
    await tester.enterText(find.byType(TextFormField), '   ');
    await tester.pump();
    await _tapVisible(tester, _save());
    expect(find.text('Enter a name'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'x' * 41);
    await tester.pump();
    await _tapVisible(tester, _save());
    expect(find.text('Use 40 characters or fewer'), findsOneWidget);
    expect(env.profiles.names, isEmpty);
  });

  testWidgets('a failed save shows the message and keeps the old profile', (
    tester,
  ) async {
    final env = await _pump(tester);
    env.profiles.failSave = const RepositoryFailure(RepositoryFailure.network);
    await _tapVisible(tester, find.widgetWithText(FilterChip, 'Advanced'));
    await _tapVisible(tester, _save());
    expect(find.text(RepositoryFailure.network), findsOneWidget);
    expect(env.container.read(profileProvider).requireValue, _stored);
    // Still dirty, so it can be retried.
    expect(tester.widget<FilledButton>(_save()).onPressed, isNotNull);
  });

  testWidgets('a failed name save keeps the saved answers and can retry', (
    tester,
  ) async {
    final env = await _pump(tester);
    env.profiles.failName = const RepositoryFailure(RepositoryFailure.generic);
    await _tapVisible(tester, find.widgetWithText(FilterChip, 'Advanced'));
    await tester.enterText(find.byType(TextFormField), 'Annie');
    await tester.pump();
    await _tapVisible(tester, _save());
    expect(find.text(RepositoryFailure.generic), findsOneWidget);
    expect(env.profiles.profiles['u1']?.level, 'Advanced');

    env.profiles.failName = null;
    await _tapVisible(tester, _save());
    expect(env.profiles.names, ['Annie']);
    expect(env.auth.nameUpdates, ['Annie']);
  });

  testWidgets('cannot save with no goal selected', (tester) async {
    await _pump(tester);
    await _tapVisible(tester, find.widgetWithText(FilterChip, 'Burn Calories'));
    expect(tester.widget<FilledButton>(_save()).onPressed, isNull);
  });

  testWidgets('sign out signs the user out', (tester) async {
    final env = await _pump(tester);
    await _tapVisible(tester, find.text('Sign out'));
    expect(env.container.read(authUserProvider), isNull);
  });

  group('delete account', () {
    Finder confirm() => find.widgetWithText(FilledButton, 'Delete');

    testWidgets('cancel does nothing', (tester) async {
      final env = await _pump(tester);
      await _tapVisible(tester, find.text('Delete account'));
      expect(find.text('Delete account?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(env.auth.deletes, 0);
      expect(find.text('Delete account?'), findsNothing);
    });

    testWidgets('confirming deletes and signs out', (tester) async {
      final env = await _pump(tester);
      await _tapVisible(tester, find.text('Delete account'));
      await tester.tap(confirm());
      await tester.pumpAndSettle();
      expect(env.auth.deletes, 1);
      expect(env.container.read(authUserProvider), isNull);
      expect(find.text('Delete account?'), findsNothing);
    });

    testWidgets('a failure shows inside the dialog and can be retried', (
      tester,
    ) async {
      final env = await _pump(tester);
      env.auth.failWith = const AuthFailure(AuthFailure.network);
      await _tapVisible(tester, find.text('Delete account'));
      await tester.tap(confirm());
      await tester.pumpAndSettle();
      expect(find.text('Delete account?'), findsOneWidget);
      expect(find.text(AuthFailure.network), findsOneWidget);
      expect(env.container.read(authUserProvider), isNotNull);

      env.auth.failWith = null;
      await tester.tap(confirm());
      await tester.pumpAndSettle();
      expect(env.auth.deletes, 1);
    });
  });

  testWidgets('loading screen offers Sign out when the profile fails', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final auth = FakeAuthRepository(FakeAuthRepository.ann);
    final profiles = FakeProfileRepository(auth)
      ..failLoad = const RepositoryFailure(RepositoryFailure.network);
    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        authRepositoryProvider.overrideWithValue(auth),
        profileRepositoryProvider.overrideWithValue(profiles),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ProfileLoadingScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Sign out'));
    // The router would leave this screen; here a spinner (no settling).
    await tester.pump();
    expect(container.read(authUserProvider), isNull);
  });
}
