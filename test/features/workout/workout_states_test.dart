import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wiggle_move/features/workout/camera_failure.dart';
import 'package:wiggle_move/features/workout/play_clock.dart';
import 'package:wiggle_move/features/workout/workout_cues.dart';
import 'package:wiggle_move/features/workout/workout_screen.dart';
import 'package:wiggle_move/shared/backend/trainer_data.dart';

void main() {
  group('cameraFailureFor', () {
    test('a refusal can be retried and points at Settings', () {
      final f = cameraFailureFor('CameraAccessDenied');
      expect(f.problem, CameraProblem.denied);
      expect(f.canRetry, isTrue);
      expect(f.message, contains('Settings'));
    });

    test('iOS permanent refusal says to open Settings', () {
      final f = cameraFailureFor('CameraAccessDeniedWithoutPrompt');
      expect(f.problem, CameraProblem.deniedForever);
      expect(f.message, contains('Open Settings'));
    });

    test('a restricted camera cannot be retried', () {
      final f = cameraFailureFor('CameraAccessRestricted');
      expect(f.problem, CameraProblem.restricted);
      expect(f.canRetry, isFalse);
    });

    test('unknown codes show the description, else the code', () {
      expect(cameraFailureFor('x', 'busy').message, 'Camera problem: busy');
      expect(cameraFailureFor('x').message, 'Camera problem: x');
      expect(cameraFailureFor('x', '').message, 'Camera problem: x');
      expect(cameraFailureFor('x').canRetry, isTrue);
    });

    test('unsupported platform and missing camera cannot be retried', () {
      expect(unsupportedPlatformFailure.canRetry, isFalse);
      expect(unsupportedPlatformFailure.message, contains('Android and iOS'));
      expect(noCameraFailure.canRetry, isFalse);
    });
  });

  group('PlayClock', () {
    test('counts only while running; pauses are excluded', () {
      var now = 1000;
      final clock = PlayClock(() => now);
      expect(clock.elapsedMs, 0);
      clock.start();
      now += 400;
      expect(clock.elapsedMs, 400);
      clock.pause();
      now += 60000; // backgrounded for a minute
      expect(clock.elapsedMs, 400);
      expect(clock.isRunning, isFalse);
      clock.start();
      now += 100;
      expect(clock.elapsedMs, 500);
    });

    test('start while running and pause while stopped are no-ops', () {
      var now = 0;
      final clock = PlayClock(() => now);
      clock.pause();
      clock.start();
      now += 50;
      clock.start();
      now += 50;
      expect(clock.elapsedMs, 100);
    });
  });

  group('workout screen states', () {
    final routine = builtInTrainers.first.routines.first;

    Future<void> pumpScreen(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [workoutCuesProvider.overrideWithValue(_NoCues())],
          child: MaterialApp(home: WorkoutScreen(routine: routine)),
        ),
      );
      await tester.pump();
    }

    testWidgets('unsupported platform explains and offers only Back', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        await pumpScreen(tester);
        expect(find.textContaining('Android and iOS'), findsOneWidget);
        expect(find.text('Try again'), findsNothing);
        expect(find.text('Back'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('Try again calls back', (tester) async {
      var tries = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProblemView(
              failure: cameraFailureFor('CameraAccessDenied'),
              onRetry: () => tries++,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Try again'));
      expect(tries, 1);
    });

    testWidgets('large text does not overflow the problem view', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2.5)),
            child: Scaffold(
              body: ProblemView(
                failure: cameraFailureFor('CameraAccessDenied'),
                onRetry: () {},
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Try again'), findsOneWidget);
    });
  });
}

class _NoCues implements WorkoutCues {
  @override
  void countdownTick() {}
  @override
  void finished() {}
  @override
  void go() {}
  @override
  void repCounted() {}
  @override
  void segmentChanged() {}
}
