import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wiggle_move/features/history/history_provider.dart';
import 'package:wiggle_move/features/history/history_screen.dart';
import 'package:wiggle_move/features/summary/summary_screen.dart';
import 'package:wiggle_move/shared/backend/auth_providers.dart';
import 'package:wiggle_move/shared/backend/content_providers.dart';
import 'package:wiggle_move/shared/backend/history_providers.dart';
import 'package:wiggle_move/shared/backend/history_repository.dart';
import 'package:wiggle_move/shared/backend/profile_repository.dart';
import 'package:wiggle_move/shared/backend/sessions_providers.dart';
import 'package:wiggle_move/shared/backend/sessions_repository.dart';
import 'package:wiggle_move/shared/backend/trainer_data.dart';
import 'package:wiggle_move/shared/prefs.dart';

import '../../support/fakes.dart';

final _routine = builtInTrainers.first.routines.first;

HistoryEntry _entry(
  String id, {
  String routine = 'pop-starter',
  int score = 80,
  DateTime? at,
  bool withResults = true,
}) => HistoryEntry(
  id: id,
  routineId: routine,
  score: score,
  durationMs: 24000,
  playedAt: at ?? DateTime(2026, 11, 25, 14, 5),
  results: withResults
      ? [
          for (var i = 0; i < _routine.moves.length; i++)
            MoveSubmission(
              moveIdx: i,
              score: i == 1 ? 40 : 90,
              worstJoint: i == 1 ? 'leftElbow' : null,
              deviation: i == 1 ? 25 : null,
            ),
        ]
      : const [],
);

Future<ProviderContainer> _pump(
  WidgetTester tester,
  FakeHistoryRepository history,
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
      historyRepositoryProvider.overrideWithValue(history),
    ],
  );
  addTearDown(container.dispose);
  final router = GoRouter(
    initialLocation: '/history',
    routes: [
      GoRoute(path: '/history', builder: (c, s) => const HistoryScreen()),
      GoRoute(
        path: '/summary',
        builder: (c, s) {
          final a = s.extra! as SummaryArgs;
          return SummaryScreen(summary: a.summary, fromHistory: a.fromHistory);
        },
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  // Let the content (routine names) load too.
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
  testWidgets('lists plays with routine name, date and score', (tester) async {
    await _pump(
      tester,
      FakeHistoryRepository([
        _entry('a', score: 80),
        _entry('b', routine: 'disco-fever', score: 55),
      ]),
    );
    expect(find.text('Pop Starter'), findsOneWidget);
    expect(find.text('Disco Fever'), findsOneWidget);
    expect(find.text('Nov 25, 2026 · 14:05'), findsNWidgets(2));
    expect(find.text('80'), findsOneWidget);
    expect(find.text('55'), findsOneWidget);
  });

  testWidgets('empty history shows the empty state', (tester) async {
    await _pump(tester, FakeHistoryRepository());
    expect(find.text(HistoryScreen.emptyText), findsOneWidget);
  });

  testWidgets('error shows a safe message and Retry refetches', (tester) async {
    final repo = FakeHistoryRepository([_entry('a')])
      ..failWith = const RepositoryFailure(RepositoryFailure.network);
    await _pump(tester, repo);
    expect(find.text(RepositoryFailure.network), findsOneWidget);

    repo.failWith = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Pop Starter'), findsOneWidget);
    expect(repo.fetches, 2);
  });

  testWidgets('tapping a play opens its stored summary', (tester) async {
    await _pump(tester, FakeHistoryRepository([_entry('a')]));
    await tester.tap(find.text('Pop Starter'));
    await tester.pumpAndSettle();
    expect(find.text('Past session'), findsOneWidget);
    // Total = mean of the stored move scores.
    final total =
        ((_routine.moves.length - 1) * 90 + 40) / _routine.moves.length;
    expect(find.text('${total.round()}'), findsWidgets);
    expect(find.textContaining('left elbow was about 25'), findsOneWidget);
    // Back returns to the list.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('History'), findsOneWidget);
  });

  testWidgets('a play without move details explains instead of opening', (
    tester,
  ) async {
    await _pump(
      tester,
      FakeHistoryRepository([_entry('a', withResults: false)]),
    );
    await tester.tap(find.text('Pop Starter'));
    await tester.pumpAndSettle();
    expect(find.text(HistoryScreen.unavailableText), findsOneWidget);
    expect(find.text('Past session'), findsNothing);
  });

  testWidgets('a play of a routine that no longer exists explains too', (
    tester,
  ) async {
    await _pump(tester, FakeHistoryRepository([_entry('a', routine: 'gone')]));
    expect(find.text('gone'), findsOneWidget); // falls back to the id
    await tester.tap(find.text('gone'));
    await tester.pumpAndSettle();
    expect(find.text(HistoryScreen.unavailableText), findsOneWidget);
  });

  testWidgets('pull to refresh refetches', (tester) async {
    final repo = FakeHistoryRepository([_entry('a')]);
    await _pump(tester, repo);
    repo.entries = [_entry('a'), _entry('b', score: 61)];
    await tester.fling(find.byType(ListView).last, const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(find.text('61'), findsOneWidget);
  });

  testWidgets('a play that finishes uploading appears in the list', (
    tester,
  ) async {
    final repo = FakeHistoryRepository();
    final container = await _pump(tester, repo);
    repo.entries = [_entry('new', score: 77)];
    await container.read(sessionSyncProvider).submit(_play('n1'));
    await tester.pumpAndSettle();
    expect(find.text('77'), findsOneWidget);
  });

  group('summaryFromHistory', () {
    test('rebuilds outcomes with joints and deviations', () {
      final s = summaryFromHistory(_entry('a'), _routine)!;
      expect(s.outcomes, hasLength(_routine.moves.length));
      expect(s.outcomes[1].result.worstJoint?.name, 'leftElbow');
      expect(s.outcomes[1].result.worstSignedDeviation, 25);
      expect(s.outcomes[0].result.worstJoint, isNull);
      expect(s.outcomes[0].result.wasVisible, isTrue);
      expect(s.outcomes[0].move, _routine.moves[0]);
    });

    test('a zero score without a joint is the never-visible case', () {
      final e = HistoryEntry(
        id: 'a',
        routineId: _routine.id,
        score: 0,
        durationMs: 1,
        playedAt: DateTime(2026),
        results: [
          for (var i = 0; i < _routine.moves.length; i++)
            MoveSubmission(moveIdx: i, score: 0),
        ],
      );
      expect(
        summaryFromHistory(e, _routine)!.outcomes[0].result.wasVisible,
        isFalse,
      );
    });

    test('an unknown joint name is ignored, not a crash', () {
      final e = HistoryEntry(
        id: 'a',
        routineId: _routine.id,
        score: 50,
        durationMs: 1,
        playedAt: DateTime(2026),
        results: [
          for (var i = 0; i < _routine.moves.length; i++)
            MoveSubmission(
              moveIdx: i,
              score: 50,
              worstJoint: 'leftEar',
              deviation: 9,
            ),
        ],
      );
      final r = summaryFromHistory(e, _routine)!.outcomes[0].result;
      expect(r.worstJoint, isNull);
      expect(r.worstSignedDeviation, isNull);
    });

    test('a changed routine or index gap is not shown', () {
      final shortRoutine = builtInTrainers.first.routines.last; // 8 moves
      expect(summaryFromHistory(_entry('a'), shortRoutine), isNull);
      expect(
        summaryFromHistory(_entry('a', withResults: false), _routine),
        isNull,
      );
      final gap = HistoryEntry(
        id: 'a',
        routineId: _routine.id,
        score: 1,
        durationMs: 1,
        playedAt: DateTime(2026),
        results: [
          for (var i = 0; i < _routine.moves.length; i++)
            MoveSubmission(moveIdx: i == 2 ? 9 : i, score: 1),
        ],
      );
      expect(summaryFromHistory(gap, _routine), isNull);
    });
  });
}
