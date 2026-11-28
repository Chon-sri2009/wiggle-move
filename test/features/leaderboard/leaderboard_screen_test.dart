import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wiggle_move/features/leaderboard/leaderboard_screen.dart';
import 'package:wiggle_move/shared/backend/auth_providers.dart';
import 'package:wiggle_move/shared/backend/content_providers.dart';
import 'package:wiggle_move/shared/backend/leaderboard_providers.dart';
import 'package:wiggle_move/shared/backend/leaderboard_repository.dart';
import 'package:wiggle_move/shared/backend/profile_repository.dart';
import 'package:wiggle_move/shared/backend/sessions_providers.dart';
import 'package:wiggle_move/shared/backend/sessions_repository.dart';
import 'package:wiggle_move/shared/prefs.dart';

import '../../support/fakes.dart';

LeaderboardRow _r(int rank, String name, int score, {bool me = false}) =>
    LeaderboardRow(rank: rank, displayName: name, score: score, isMe: me);

Future<ProviderContainer> _pump(
  WidgetTester tester,
  FakeLeaderboardRepository board,
) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(FakeAuthRepository.ann),
      ),
      contentRepositoryProvider.overrideWithValue(FakeContentRepository()),
      sessionsRepositoryProvider.overrideWithValue(FakeSessionsRepository()),
      leaderboardRepositoryProvider.overrideWithValue(board),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: LeaderboardScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

SessionSubmission _play(String nonce) => SessionSubmission(
  routineId: 'pop-starter',
  clientNonce: nonce,
  durationMs: 24000,
  score: 77,
  playedAt: DateTime.utc(2026),
  userId: 'u1',
  results: const [MoveSubmission(moveIdx: 0, score: 77)],
);

void main() {
  testWidgets('renders ranked rows, ties as given, and marks me', (
    tester,
  ) async {
    final board = FakeLeaderboardRepository([
      _r(1, 'Bo', 90),
      _r(1, 'Cy', 90),
      _r(3, 'Ann', 40, me: true),
    ]);
    await _pump(tester, board);
    expect(find.text('Bo'), findsOneWidget);
    expect(find.text('Cy'), findsOneWidget);
    expect(find.text('Ann (you)'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('90'), findsNWidgets(2));
    final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    expect(tiles.map((t) => t.selected), [false, false, true]);
    expect(board.calls, [(routineId: null, period: LeaderboardPeriod.all)]);
  });

  testWidgets('empty board shows the play-a-routine message', (tester) async {
    await _pump(tester, FakeLeaderboardRepository());
    expect(find.text('No scores yet — play a routine'), findsOneWidget);
  });

  testWidgets('error shows a safe message and Retry refetches', (tester) async {
    final board = FakeLeaderboardRepository([_r(1, 'Bo', 9)])
      ..failWith = const RepositoryFailure(RepositoryFailure.network);
    await _pump(tester, board);
    expect(find.text(RepositoryFailure.network), findsOneWidget);
    expect(find.text('Bo'), findsNothing);

    board.failWith = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Bo'), findsOneWidget);
    expect(board.calls, hasLength(2));
  });

  testWidgets('shows a spinner while loading', (tester) async {
    final board = FakeLeaderboardRepository()..gate = Completer<void>();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
          contentRepositoryProvider.overrideWithValue(FakeContentRepository()),
          leaderboardRepositoryProvider.overrideWithValue(board),
        ],
        child: const MaterialApp(home: LeaderboardScreen()),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    board.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('the Cardio chip asks for that category and narrows routines', (
    tester,
  ) async {
    final board = FakeLeaderboardRepository([_r(1, 'Bo', 9)]);
    await _pump(tester, board);
    expect(find.widgetWithText(ChoiceChip, 'Pop Starter'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Squat Sets'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Cardio'));
    await tester.pumpAndSettle();
    expect(board.categories.last, 'cardio');
    expect(find.widgetWithText(ChoiceChip, 'Pop Starter'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'Squat Sets'), findsOneWidget);

    // Picking a routine keeps the category; changing category clears it.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Squat Sets'));
    await tester.pumpAndSettle();
    expect(board.calls.last.routineId, 'squat-sets');
    expect(board.categories.last, 'cardio');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Dance'));
    await tester.pumpAndSettle();
    expect(board.calls.last.routineId, isNull);
    expect(board.categories.last, 'dance');

    await tester.tap(find.widgetWithText(ChoiceChip, 'All types'));
    await tester.pumpAndSettle();
    expect(board.categories.last, isNull);
  });

  testWidgets('switching period and routine refetches with those params', (
    tester,
  ) async {
    final board = FakeLeaderboardRepository([_r(1, 'Bo', 9)]);
    await _pump(tester, board);
    board.byQuery = {
      (routineId: null, period: LeaderboardPeriod.week): [_r(1, 'Wk', 5)],
      (routineId: 'pop-starter', period: LeaderboardPeriod.week): [
        _r(1, 'Routine', 7),
      ],
    };

    await tester.tap(find.text('Weekly'));
    await tester.pumpAndSettle();
    expect(find.text('Wk'), findsOneWidget);
    expect(find.text('Bo'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Pop Starter'));
    await tester.pumpAndSettle();
    expect(find.text('Routine'), findsOneWidget);
    expect(board.calls.last, (
      routineId: 'pop-starter',
      period: LeaderboardPeriod.week,
    ));

    await tester.tap(find.text('All-time'));
    await tester.pumpAndSettle();
    expect(board.calls.last, (
      routineId: 'pop-starter',
      period: LeaderboardPeriod.all,
    ));
  });

  testWidgets('a late response for an old selection does not overwrite', (
    tester,
  ) async {
    final board = FakeLeaderboardRepository([_r(1, 'AllRow', 1)]);
    await _pump(tester, board);
    final slow = Completer<void>();
    board.gate = slow;
    board.byQuery = {
      (routineId: null, period: LeaderboardPeriod.week): [_r(1, 'Stale', 5)],
    };
    await tester.tap(find.text('Weekly'));
    await tester.pump();
    // Back to all-time before the weekly response lands.
    await tester.tap(find.text('All-time'));
    await tester.pump();
    slow.complete();
    await tester.pumpAndSettle();
    expect(find.text('Stale'), findsNothing);
    expect(find.text('AllRow'), findsOneWidget);
  });

  testWidgets('pull to refresh refetches', (tester) async {
    final board = FakeLeaderboardRepository([_r(1, 'Bo', 9)]);
    await _pump(tester, board);
    board.rows = [_r(1, 'Bo', 9), _r(2, 'Di', 8)];
    await tester.fling(find.byType(ListView).last, const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Di'), findsOneWidget);
    expect(board.calls, hasLength(2));
  });

  testWidgets('refetches after one of my plays is saved', (tester) async {
    final board = FakeLeaderboardRepository([_r(1, 'Bo', 9)]);
    final container = await _pump(tester, board);
    board.rows = [_r(1, 'Ann', 77, me: true)];

    await container.read(sessionSyncProvider).submit(_play('n1'));
    await tester.pumpAndSettle();
    expect(find.text('Ann (you)'), findsOneWidget);
    expect(board.calls, hasLength(2));
  });

  testWidgets('a queued (not saved) play does not refetch', (tester) async {
    final board = FakeLeaderboardRepository([_r(1, 'Bo', 9)]);
    final container = await _pump(tester, board);
    (container.read(sessionsRepositoryProvider) as FakeSessionsRepository)
        .script
        .addAll(const [
          SubmitRetryable(RetryReason.network),
          SubmitRetryable(RetryReason.network),
        ]);
    await container.read(sessionSyncProvider).submit(_play('n2'));
    await tester.pumpAndSettle();
    expect(board.calls, hasLength(1));
  });
}
