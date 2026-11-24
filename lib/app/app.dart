import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/home/home_screen.dart';
import '../features/leaderboard/leaderboard_screen.dart';
import '../features/summary/summary_screen.dart';
import '../features/trainers/trainer_data.dart';
import '../features/trainers/trainer_screen.dart';
import '../features/workout/workout_screen.dart';
import '../features/workout/workout_session.dart';

class _NotFound extends StatelessWidget {
  const _NotFound();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(),
    body: const Center(child: Text('Not found')),
  );
}

GoRouter _buildRouter() => GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
    GoRoute(
      path: '/trainer/:id',
      builder: (context, state) {
        final trainer = trainerById(state.pathParameters['id']!);
        return trainer == null
            ? const _NotFound()
            : TrainerScreen(trainer: trainer);
      },
    ),
    GoRoute(
      path: '/workout/:routineId',
      builder: (context, state) {
        final routine = routineById(state.pathParameters['routineId']!);
        return routine == null
            ? const _NotFound()
            : WorkoutScreen(routine: routine);
      },
    ),
    GoRoute(
      path: '/summary',
      builder: (context, state) {
        final summary = state.extra;
        return summary is SessionSummary
            ? SummaryScreen(summary: summary)
            : const _NotFound();
      },
    ),
    GoRoute(
      path: '/leaderboard',
      builder: (context, state) => const LeaderboardScreen(),
    ),
  ],
);

class WiggleMoveApp extends StatefulWidget {
  const WiggleMoveApp({super.key});

  @override
  State<WiggleMoveApp> createState() => _WiggleMoveAppState();
}

class _WiggleMoveAppState extends State<WiggleMoveApp> {
  final _router = _buildRouter();

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Wiggle Move',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      routerConfig: _router,
    );
  }
}
