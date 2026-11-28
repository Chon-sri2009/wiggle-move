import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wiggle_move/features/summary/summary_screen.dart';
import 'package:wiggle_move/features/workout/workout_session.dart';
import 'package:wiggle_move/shared/backend/sessions_providers.dart';
import 'package:wiggle_move/shared/backend/sessions_repository.dart';
import 'package:wiggle_move/shared/backend/trainer_data.dart';

const _nonce = 'n1';

SessionSummary _summary() {
  final s = WorkoutSession(builtInTrainers.first.routines.first);
  s.advance(s.routine.durationMs);
  return s.summary();
}

Future<ProviderContainer> _pump(WidgetTester tester, {String? id}) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: SummaryScreen(summary: _summary(), submissionId: id),
      ),
    ),
  );
  return container;
}

void main() {
  testWidgets('shows upload status as it changes, summary stays visible', (
    tester,
  ) async {
    final c = await _pump(tester, id: _nonce);
    final status = c.read(submissionStatusProvider.notifier);
    expect(find.text('Move by move'), findsOneWidget);

    status.set(_nonce, const SubmissionState(SubmissionStatus.pending));
    await tester.pump();
    expect(find.text(SummaryScreen.savingText), findsOneWidget);

    status.set(_nonce, const SubmissionState(SubmissionStatus.queued));
    await tester.pump();
    expect(find.text(SummaryScreen.queuedText), findsOneWidget);

    status.set(_nonce, const SubmissionState(SubmissionStatus.saved));
    await tester.pump();
    expect(find.text(SummaryScreen.savedText), findsOneWidget);
    expect(find.text('Move by move'), findsOneWidget);
  });

  testWidgets('rejected shows the safe message', (tester) async {
    final c = await _pump(tester, id: _nonce);
    c
        .read(submissionStatusProvider.notifier)
        .set(
          _nonce,
          const SubmissionState(
            SubmissionStatus.rejected,
            SubmitRejected.routineGone,
          ),
        );
    await tester.pump();
    expect(find.text(SubmitRejected.routineGone), findsOneWidget);
  });

  testWidgets('no submission (signed out): no status line', (tester) async {
    await _pump(tester);
    expect(find.text(SummaryScreen.savingText), findsNothing);
    expect(find.text(SummaryScreen.savedText), findsNothing);
  });
}
