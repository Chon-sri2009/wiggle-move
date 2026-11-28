import 'package:camera/camera.dart' show CameraException;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wiggle_move/features/summary/summary_screen.dart';
import 'package:wiggle_move/features/workout/form/form_feedback.dart';
import 'package:wiggle_move/features/workout/play_clock.dart';
import 'package:wiggle_move/features/workout/workout_camera.dart';
import 'package:wiggle_move/features/workout/workout_cues.dart';
import 'package:wiggle_move/features/workout/workout_screen.dart';
import 'package:wiggle_move/shared/backend/auth_providers.dart';
import 'package:wiggle_move/shared/backend/content_models.dart';
import 'package:wiggle_move/shared/backend/sessions_providers.dart';
import 'package:wiggle_move/shared/prefs.dart';
import 'package:wiggle_move/shared/pose/pose_math.dart';

import '../../support/fakes.dart';

const _routine = Routine(
  id: 'r',
  name: 'Quick',
  level: 'Easy',
  moves: [
    Move(
      name: 'Arms up',
      instruction: 'Reach high',
      durationMs: 1000,
      target: MoveTarget({Joint.leftShoulder: 165}),
    ),
  ],
);

class _FakeCamera implements WorkoutCamera {
  _FakeCamera(this.openError);
  final Object? openError;
  void Function(Map<Joint, double>)? listener;
  bool open_ = false;
  bool closed = false;

  @override
  Future<void> open() async {
    if (openError != null) throw openError!;
    open_ = true;
  }

  @override
  bool get isOpen => open_;

  @override
  Widget buildPreview() => const SizedBox.expand();

  @override
  double get previewAspect => 3 / 4;

  @override
  Future<void> startFrames(
    void Function(Map<Joint, double> angles) onAngles,
  ) async => listener = onAngles;

  @override
  Future<void> stopFrames() async => listener = null;

  @override
  final formFeedback = ValueNotifier<FormFeedback?>(null);

  @override
  Future<void> close() async => closed = true;
}

class _Cues implements WorkoutCues {
  final events = <String>[];
  @override
  void countdownTick() => events.add('tick');
  @override
  void finished() => events.add('finished');
  @override
  void go() => events.add('go');
  @override
  void repCounted() => events.add('rep');
  @override
  void segmentChanged() => events.add('segment');
}

class _Harness {
  _Harness({this.openErrors = const []});

  /// Errors the 1st, 2nd... camera open throws; none left = opens fine.
  final List<Object> openErrors;
  final cameras = <_FakeCamera>[];
  final cues = _Cues();
  final sessions = FakeSessionsRepository();
  late SharedPreferences prefs;
  int nowMs = 0;

  Widget app() {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () => context.push('/workout'),
              child: const Text('Go'),
            ),
          ),
        ),
        GoRoute(
          path: '/workout',
          builder: (_, _) => const WorkoutScreen(routine: _routine),
        ),
        GoRoute(
          path: '/summary',
          builder: (_, state) {
            final s = (state.extra as SummaryArgs).summary;
            return Scaffold(
              body: Text('SUMMARY ${s.totalScore} in ${s.durationMs}ms'),
            );
          },
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(FakeAuthRepository.ann),
        ),
        sessionsRepositoryProvider.overrideWithValue(sessions),
        workoutCuesProvider.overrideWithValue(cues),
        playNowMsProvider.overrideWithValue(() => nowMs),
        workoutCameraFactoryProvider.overrideWithValue(() {
          final i = cameras.length;
          final cam = _FakeCamera(i < openErrors.length ? openErrors[i] : null);
          cameras.add(cam);
          return cam;
        }),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  /// Advances fake time and the widget clock together.
  Future<void> elapse(WidgetTester tester, int ms) async {
    nowMs += ms;
    await tester.pump(Duration(milliseconds: ms));
  }

  Future<void> start(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(app());
    await tester.tap(find.text('Go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // route + open()
  }

  /// Counts the 3-second countdown down; the workout is running afterwards.
  Future<void> countdown(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await elapse(tester, 1000);
    }
  }
}

/// A widget test on Android (where the workout runs). The platform override
/// is cleared inside the test body: the framework checks it before tearDown.
void flowTest(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void main() {
  flowTest('plays the countdown and the move, then shows the summary', (
    tester,
  ) async {
    final h = _Harness();
    await h.start(tester);
    expect(find.text('3'), findsOneWidget);
    await h.countdown(tester);
    expect(h.cameras.single.listener, isNotNull, reason: 'frames flowing');
    expect(find.text('Arms up'), findsOneWidget);
    expect(find.text('Move 1 of 1'), findsOneWidget);

    // A perfect pose frame is scored; then the move's 1 s runs out.
    h.cameras.single.listener!({Joint.leftShoulder: 165});
    await tester.pump();
    for (var i = 0; i < 11; i++) {
      await h.elapse(tester, 100);
    }
    await tester.pumpAndSettle();
    expect(find.textContaining('SUMMARY 100'), findsOneWidget);
    expect(h.cues.events, [
      'tick',
      'tick',
      'tick',
      'go',
      'finished',
    ], reason: 'one move: no segment change before the end');
    final sent = h.sessions.submitted.single;
    expect(sent.score, 100);
    expect(sent.durationMs, inInclusiveRange(1000, 1200));
  });

  flowTest('pausing excludes the paused time from the play duration', (
    tester,
  ) async {
    final h = _Harness();
    await h.start(tester);
    await h.countdown(tester);
    await h.elapse(tester, 300);

    await tester.tap(find.byTooltip('Pause workout'));
    await tester.pump();
    expect(find.text('Paused'), findsOneWidget);
    expect(h.cameras.single.listener, isNull, reason: 'frames stopped');
    await h.elapse(tester, 60000); // away for a minute
    expect(find.text('Paused'), findsOneWidget);

    await tester.tap(find.text('Resume'));
    await tester.pump();
    expect(find.text('Paused'), findsNothing);
    expect(h.cameras.single.listener, isNotNull);
    for (var i = 0; i < 8; i++) {
      await h.elapse(tester, 100);
    }
    await tester.pumpAndSettle();
    final text = tester
        .widget<Text>(find.textContaining('SUMMARY'))
        .data!; // "SUMMARY 0 in 1100ms"
    final ms = int.parse(RegExp(r'in (\d+)ms').firstMatch(text)!.group(1)!);
    expect(ms, inInclusiveRange(1000, 1200), reason: text);
    expect(h.sessions.submitted.single.durationMs, ms);
  });

  flowTest('leaving the app pauses; Resume carries on', (tester) async {
    final h = _Harness();
    await h.start(tester);
    await h.countdown(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('Paused'), findsOneWidget, reason: 'stays paused');
    await tester.tap(find.text('Resume'));
    await tester.pump();
    expect(find.text('Paused'), findsNothing);
  });

  flowTest('back asks first; Keep going resumes, Quit leaves', (tester) async {
    final h = _Harness();
    await h.start(tester);
    await h.countdown(tester);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Quit workout?'), findsOneWidget);
    await tester.tap(find.text('Keep going'));
    await tester.pumpAndSettle();
    expect(find.text('Quit workout?'), findsNothing);
    expect(find.text('Paused'), findsNothing, reason: 'resumed');
    expect(h.cameras.single.listener, isNotNull);

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.tap(find.text('Quit'));
    await tester.pumpAndSettle();
    expect(find.text('Go'), findsOneWidget);
    expect(find.textContaining('SUMMARY'), findsNothing, reason: 'not saved');
  });

  flowTest('a denied camera offers Try again, which opens a new camera', (
    tester,
  ) async {
    final h = _Harness(openErrors: [CameraException('CameraAccessDenied', '')]);
    await h.start(tester);
    expect(find.textContaining('needs the camera'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(h.cameras, hasLength(2));
    expect(h.cameras.first.closed, isTrue);
    expect(find.textContaining('needs the camera'), findsNothing);
    expect(find.text('3'), findsOneWidget, reason: 'countdown restarted');
  });

  flowTest('no camera at all offers only Back', (tester) async {
    final h = _Harness(openErrors: [const NoCameraException()]);
    await h.start(tester);
    expect(find.textContaining('No camera was found'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Go'), findsOneWidget);
  });
}
