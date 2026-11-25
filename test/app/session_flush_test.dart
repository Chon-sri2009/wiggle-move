import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wiggle_move/app/app.dart';
import 'package:wiggle_move/shared/backend/auth_providers.dart';
import 'package:wiggle_move/shared/backend/content_providers.dart';
import 'package:wiggle_move/shared/backend/pending_submission_queue.dart';
import 'package:wiggle_move/shared/backend/profile_providers.dart';
import 'package:wiggle_move/shared/backend/sessions_providers.dart';
import 'package:wiggle_move/shared/backend/sessions_repository.dart';
import 'package:wiggle_move/shared/prefs.dart';

import '../support/fakes.dart';

final _queued = SessionSubmission(
  routineId: 'mia-pop',
  clientNonce: '00000000-0000-4000-8000-000000000001',
  durationMs: 24000,
  score: 50,
  playedAt: DateTime.utc(2026),
  userId: 'u1',
  results: const [MoveSubmission(moveIdx: 0, score: 50)],
);

late SharedPreferences _prefs;

/// The app with one queued play for u1 and [repo] as the sessions backend.
Future<Widget> _app(
  FakeSessionsRepository repo,
  FakeAuthRepository auth,
) async {
  SharedPreferences.setMockInitialValues({});
  _prefs = await SharedPreferences.getInstance();
  await PendingSubmissionQueue(_prefs).enqueue(_queued);
  return ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(_prefs),
      authRepositoryProvider.overrideWithValue(auth),
      profileRepositoryProvider.overrideWithValue(
        FakeProfileRepository(auth, {'u1': FakeProfileRepository.onboarded}),
      ),
      contentRepositoryProvider.overrideWithValue(FakeContentRepository()),
      sessionsRepositoryProvider.overrideWithValue(repo),
    ],
    child: const WiggleMoveApp(),
  );
}

void main() {
  testWidgets('app start with a signed-in user flushes the queue', (
    tester,
  ) async {
    final repo = FakeSessionsRepository();
    await tester.pumpWidget(
      await _app(repo, FakeAuthRepository(FakeAuthRepository.ann)),
    );
    await tester.pumpAndSettle();
    expect(repo.submitted.single.clientNonce, _queued.clientNonce);
    expect(PendingSubmissionQueue(_prefs).entries(), isEmpty);
  });

  testWidgets('app resume retries what failed before', (tester) async {
    final repo = FakeSessionsRepository()
      ..script.add(const SubmitRetryable(RetryReason.network));
    await tester.pumpWidget(
      await _app(repo, FakeAuthRepository(FakeAuthRepository.ann)),
    );
    await tester.pumpAndSettle();
    expect(repo.submitted, hasLength(1));
    expect(PendingSubmissionQueue(_prefs).entries(), hasLength(1));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(repo.submitted, hasLength(2));
    expect(PendingSubmissionQueue(_prefs).entries(), isEmpty);
  });

  testWidgets('sign-in flushes; signed out sends nothing', (tester) async {
    final repo = FakeSessionsRepository();
    final auth = FakeAuthRepository();
    await tester.pumpWidget(await _app(repo, auth));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(repo.submitted, isEmpty);

    auth.emit(FakeAuthRepository.ann);
    await tester.pumpAndSettle();
    expect(repo.submitted.single.clientNonce, _queued.clientNonce);
  });
}
