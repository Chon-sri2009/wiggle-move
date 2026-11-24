import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_screens.dart';
import '../features/leaderboard/leaderboard_store.dart';
import '../features/profile/personalize_screen.dart';
import '../features/profile/profile_store.dart';
import 'theme.dart';

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

const _authPaths = {'/login', '/signup'};

GoRouter _buildRouter(WidgetRef ref, Listenable refresh) => GoRouter(
  refreshListenable: refresh,
  redirect: (context, state) {
    final signedIn = ref.read(playerNameProvider) != null;
    final onboarded = ref.read(profileProvider).onboarded;
    final loc = state.matchedLocation;
    if (!signedIn) return _authPaths.contains(loc) ? null : '/login';
    if (_authPaths.contains(loc)) return onboarded ? '/' : '/personalize';
    if (!onboarded && loc != '/personalize') return '/personalize';
    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (c, s) => const AuthScreen(signUp: false)),
    GoRoute(path: '/signup', builder: (c, s) => const AuthScreen(signUp: true)),
    GoRoute(path: '/personalize', builder: (c, s) => const PersonalizeScreen()),
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

class WiggleMoveApp extends ConsumerStatefulWidget {
  const WiggleMoveApp({super.key});

  @override
  ConsumerState<WiggleMoveApp> createState() => _WiggleMoveAppState();
}

class _WiggleMoveAppState extends ConsumerState<WiggleMoveApp> {
  final _refresh = ValueNotifier(0);
  late final GoRouter _router = _buildRouter(ref, _refresh);

  @override
  void dispose() {
    _router.dispose();
    _refresh.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Re-run route redirects when sign-in or onboarding state changes.
    ref.listen(playerNameProvider, (_, _) => _refresh.value++);
    ref.listen(profileProvider, (_, _) => _refresh.value++);
    return MaterialApp.router(
      title: 'Wiggle Move',
      theme: buildTheme(),
      routerConfig: _router,
    );
  }
}
