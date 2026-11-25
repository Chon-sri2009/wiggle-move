import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wiggle_move/app/app.dart';
import 'package:wiggle_move/shared/backend/auth_providers.dart';
import 'package:wiggle_move/shared/backend/content_cache.dart';
import 'package:wiggle_move/shared/backend/content_providers.dart';
import 'package:wiggle_move/shared/backend/profile_providers.dart';
import 'package:wiggle_move/shared/backend/profile_repository.dart';
import 'package:wiggle_move/shared/backend/trainer_data.dart';
import 'package:wiggle_move/shared/prefs.dart';

import '../../support/fakes.dart';

/// Signed-in, onboarded user on Home with [content] as the backend.
Future<Widget> _app(
  FakeContentRepository content, {
  bool cached = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  if (cached) await ContentCache(prefs).save([builtInTrainers.first]);
  final auth = FakeAuthRepository(FakeAuthRepository.ann);
  return ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      authRepositoryProvider.overrideWithValue(auth),
      profileRepositoryProvider.overrideWithValue(
        FakeProfileRepository(auth, {'u1': FakeProfileRepository.onboarded}),
      ),
      contentRepositoryProvider.overrideWithValue(content),
    ],
    child: const WiggleMoveApp(),
  );
}

void main() {
  testWidgets('home shows trainers from the content repository', (
    tester,
  ) async {
    await tester.pumpWidget(
      await _app(FakeContentRepository([builtInTrainers.last])),
    );
    await tester.pumpAndSettle();
    expect(find.text('Coach Jay'), findsOneWidget);
    expect(find.text('Coach Mia'), findsNothing);
    expect(find.textContaining('offline'), findsNothing);
  });

  testWidgets('no cache + failure shows an error; Retry loads content', (
    tester,
  ) async {
    final repo = FakeContentRepository()
      ..failWith = const RepositoryFailure(RepositoryFailure.network);
    await tester.pumpWidget(await _app(repo));
    await tester.pumpAndSettle();
    expect(find.text(RepositoryFailure.network), findsOneWidget);
    expect(find.text('Coach Mia'), findsNothing);

    repo.failWith = null;
    await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
    await tester.pumpAndSettle();
    expect(find.text(RepositoryFailure.network), findsNothing);
    expect(find.text('Coach Mia'), findsOneWidget);
    expect(find.text('Coach Jay'), findsOneWidget);
  });

  testWidgets('failure with a cache shows saved content and a note', (
    tester,
  ) async {
    final repo = FakeContentRepository()
      ..failWith = const RepositoryFailure(RepositoryFailure.network);
    await tester.pumpWidget(await _app(repo, cached: true));
    await tester.pumpAndSettle();
    expect(find.text('Coach Mia'), findsOneWidget);
    expect(find.textContaining('offline'), findsOneWidget);

    // Pull to refresh once the connection is back.
    repo.failWith = null;
    await tester.fling(find.text('Coach Mia'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Coach Jay'), findsOneWidget);
    expect(find.textContaining('offline'), findsNothing);
  });

  testWidgets('trainer route opens content from the provider', (tester) async {
    await tester.pumpWidget(await _app(FakeContentRepository()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Coach Jay'));
    await tester.pumpAndSettle();
    expect(find.text('Cardio Burn'), findsOneWidget);
  });
}
