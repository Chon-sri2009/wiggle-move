import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wiggle_move/features/history/history_provider.dart';
import 'package:wiggle_move/features/summary/summary_screen.dart';
import 'package:wiggle_move/features/trainers/trainer_screen.dart';
import 'package:wiggle_move/features/workout/workout_session.dart';
import 'package:wiggle_move/shared/backend/history_repository.dart';
import 'package:wiggle_move/shared/backend/sessions_repository.dart';
import 'package:wiggle_move/shared/backend/trainer_data.dart';
import 'package:wiggle_move/shared/pose/pose_math.dart';

final _squatSets = builtInTrainers
    .expand((t) => t.routines)
    .firstWhere((r) => r.id == 'squat-sets');
final _pop = builtInTrainers.first.routines.first;

/// Plays every set of Squat Sets with [reps] full squats in each.
SessionSummary _played({required int reps}) {
  final s = WorkoutSession(_squatSets);
  final r = _squatSets;
  var t = 0;
  for (var set = 0; set < r.sets; set++) {
    for (var i = 0; i < reps; i++) {
      s.addFrame({Joint.leftKnee: 95, Joint.rightKnee: 95});
      s.addFrame({Joint.leftKnee: 170, Joint.rightKnee: 170});
    }
    t += r.durationMs;
    s.advance(t);
    if (set < r.sets - 1) {
      t += r.restMs;
      s.advance(t);
    }
  }
  return s.summary(durationMs: r.totalDurationMs);
}

Widget _app(Widget home) => ProviderScope(child: MaterialApp(home: home));

Future<void> _tall(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('a cardio summary shows sets, reps and a kcal estimate', (
    tester,
  ) async {
    await _tall(tester);
    await tester.pumpWidget(_app(SummaryScreen(summary: _played(reps: 12))));
    // 3 sets x 12 reps asked, 36 done; 130 s at 5 MET is about 13 kcal.
    expect(
      find.text('3 sets · 36 / 36 reps · 2:10 active · ≈ 13 kcal (estimate)'),
      findsOneWidget,
    );
    expect(find.text('Reps 36 / 36'), findsOneWidget);
  });

  testWidgets('missing reps show on the move and lower the score', (
    tester,
  ) async {
    await _tall(tester);
    final summary = _played(reps: 6); // half the reps every set
    expect(summary.totalScore, 50);
    await tester.pumpWidget(_app(SummaryScreen(summary: summary)));
    expect(find.text('Reps 18 / 36'), findsOneWidget);
  });

  testWidgets('a dance summary has no sets or reps line', (tester) async {
    await _tall(tester);
    final s = WorkoutSession(_pop)..advance(_pop.durationMs);
    await tester.pumpWidget(
      _app(SummaryScreen(summary: s.summary(durationMs: 1000))),
    );
    expect(find.textContaining('reps'), findsNothing);
    expect(find.textContaining('sets'), findsNothing);
  });

  testWidgets('the trainer screen shows sets and the whole duration', (
    tester,
  ) async {
    final jay = builtInTrainers.last;
    await tester.pumpWidget(_app(TrainerScreen(trainer: jay)));
    // 3 x 30 s + 2 x 20 s rests = 130 s.
    expect(find.text('Easy · 1 moves · 3 sets · 130s'), findsOneWidget);
    expect(find.text('Medium · 6 moves · 24s'), findsOneWidget);
  });

  group('summaryFromHistory with sets and reps', () {
    HistoryEntry entry({int sets = 3, int reps = 30}) => HistoryEntry(
      id: 'a',
      routineId: _squatSets.id,
      score: 80,
      durationMs: 130000,
      playedAt: DateTime(2026),
      sets: sets,
      results: [MoveSubmission(moveIdx: 0, score: 80, reps: reps)],
    );

    test('restores reps and the duration for the calorie estimate', () {
      final s = summaryFromHistory(entry(), _squatSets)!;
      expect(s.totalReps, 30);
      expect(s.targetReps, 36);
      expect(s.durationMs, 130000);
      expect(s.outcomes.single.result.wasVisible, isTrue);
    });

    test('a score of 0 with reps counted was still visible', () {
      final s = summaryFromHistory(entry(reps: 2), _squatSets)!;
      expect(s.outcomes.single.result.reps, 2);
      final zero = HistoryEntry(
        id: 'a',
        routineId: _squatSets.id,
        score: 0,
        durationMs: 1,
        playedAt: DateTime(2026),
        sets: 3,
        results: const [MoveSubmission(moveIdx: 0, score: 0, reps: 2)],
      );
      expect(
        summaryFromHistory(zero, _squatSets)!.outcomes.single.result.wasVisible,
        isTrue,
      );
    });

    test('a play of a routine whose sets changed is not shown', () {
      expect(summaryFromHistory(entry(sets: 2), _squatSets), isNull);
    });
  });
}
