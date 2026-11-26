import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_screens.dart';
import '../features/profile/personalize_screen.dart';
import '../features/profile/profile_loading_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/profile/profile_store.dart';
import '../shared/backend/auth_providers.dart';
import '../shared/backend/content_models.dart';
import '../shared/backend/profile.dart';
import '../shared/backend/sessions_providers.dart';
import 'theme.dart';

import '../features/history/history_screen.dart';
import '../features/home/home_screen.dart';
import '../features/leaderboard/leaderboard_screen.dart';
import '../features/summary/summary_screen.dart';
import '../features/trainers/content_gate.dart';
import '../features/trainers/trainer_screen.dart';
import '../features/trainers/trainers_provider.dart';
import '../features/workout/workout_screen.dart';

class _NotFound extends StatelessWidget {
  const _NotFound();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(),
    body: const Center(child: Text('Not found')),
  );
}

const _authPaths = {'/login', '/signup'};
const _loadingPath = '/loading';

/// Where the router sends [location], or null to stay. Signed-out users go
/// to login; while the profile is loading (or failed to load) a signed-in
/// user waits on [_loadingPath] so onboarding is decided by the server
/// answer, not a default; users who are not onboarded go to /personalize.
String? appRedirect({
  required bool signedIn,
  required AsyncValue<Profile> profile,
  required String location,
}) {
  if (!signedIn) return _authPaths.contains(location) ? null : '/login';
  // isLoading also covers a reload that still carries the previous value.
  if (profile.isLoading || profile.hasError) {
    return location == _loadingPath ? null : _loadingPath;
  }
  final onboarded = profile.requireValue.onboarded;
  if (_authPaths.contains(location) || location == _loadingPath) {
    return onboarded ? '/' : '/personalize';
  }
  if (!onboarded && location != '/personalize') return '/personalize';
  return null;
}

GoRouter _buildRouter(WidgetRef ref, Listenable refresh) => GoRouter(
  refreshListenable: refresh,
  redirect: (context, state) => appRedirect(
    signedIn: ref.read(authUserProvider) != null,
    profile: ref.read(profileProvider),
    location: state.matchedLocation,
  ),
  routes: [
    GoRoute(
      path: _loadingPath,
      builder: (c, s) => const ProfileLoadingScreen(),
    ),
    GoRoute(path: '/login', builder: (c, s) => const AuthScreen(signUp: false)),
    GoRoute(path: '/signup', builder: (c, s) => const AuthScreen(signUp: true)),
    GoRoute(path: '/personalize', builder: (c, s) => const PersonalizeScreen()),
    GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
    GoRoute(path: '/profile', builder: (c, s) => const ProfileScreen()),
    GoRoute(
      path: '/trainer/:id',
      builder: (context, state) => ContentGate<Trainer>(
        lookup: trainerProvider(state.pathParameters['id']!),
        builder: (trainer) => TrainerScreen(trainer: trainer),
        notFound: const _NotFound(),
      ),
    ),
    GoRoute(
      path: '/workout/:routineId',
      builder: (context, state) => ContentGate<Routine>(
        lookup: routineProvider(state.pathParameters['routineId']!),
        builder: (routine) => WorkoutScreen(routine: routine),
        notFound: const _NotFound(),
      ),
    ),
    GoRoute(
      path: '/summary',
      builder: (context, state) {
        final args = state.extra;
        return args is SummaryArgs
            ? SummaryScreen(
                summary: args.summary,
                submissionId: args.submissionId,
                fromHistory: args.fromHistory,
              )
            : const _NotFound();
      },
    ),
    GoRoute(path: '/history', builder: (c, s) => const HistoryScreen()),
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

class _WiggleMoveAppState extends ConsumerState<WiggleMoveApp>
    with WidgetsBindingObserver {
  final _refresh = ValueNotifier(0);
  late final GoRouter _router = _buildRouter(ref, _refresh);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // App start: upload plays queued while offline (if signed in).
    WidgetsBinding.instance.addPostFrameCallback((_) => _flushPending());
  }

  void _flushPending() {
    if (mounted) unawaited(ref.read(sessionSyncProvider).flush());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _flushPending();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _router.dispose();
    _refresh.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Re-run route redirects when sign-in or onboarding state changes.
    ref.listen(authUserProvider, (prev, next) {
      _refresh.value++;
      // Sign-in (or account switch): upload that user's queued plays.
      if (next != null && next.id != prev?.id) _flushPending();
    });
    ref.listen(profileProvider, (_, _) => _refresh.value++);
    return MaterialApp.router(
      title: 'Wiggle Move',
      theme: buildTheme(),
      routerConfig: _router,
    );
  }
}
