import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/backend/content_models.dart';
import '../../shared/backend/content_providers.dart';
import '../../shared/backend/content_repository.dart';
import '../../shared/backend/profile_repository.dart';

/// Content shown to the user. [refreshError] is set when [trainers] is the
/// saved copy because the latest fetch failed (UI shows an "offline" note).
class TrainersState {
  const TrainersState(this.trainers, {this.refreshError});
  final List<Trainer> trainers;
  final RepositoryFailure? refreshError;

  bool get isStale => refreshError != null;
}

/// Stale-while-revalidate: emits the cached content at once (if any), then
/// fetches; success replaces and re-caches it, failure keeps the cached copy
/// and marks it stale. With no cache a failure is an [AsyncError] (Retry).
class TrainersNotifier extends AsyncNotifier<TrainersState> {
  @override
  FutureOr<TrainersState> build() {
    final cached = ref.watch(contentCacheProvider).read();
    if (cached == null) return _fetch();
    unawaited(_revalidate(cached.trainers));
    return TrainersState(cached.trainers);
  }

  /// Pull-to-refresh / Retry. Never throws; the outcome is in [state].
  Future<void> refresh() async {
    final current = state.value;
    if (current != null) return _revalidate(current.trainers);
    ref.invalidateSelf();
    try {
      await future;
    } catch (_) {
      // Shown as the error state.
    }
  }

  Future<TrainersState> _fetch() async {
    final ContentRepository repo = ref.read(contentRepositoryProvider);
    final cache = ref.read(contentCacheProvider);
    final List<Trainer> trainers;
    try {
      trainers = await repo.fetchTrainers();
    } catch (e) {
      throw mapRepositoryException(e);
    }
    try {
      await cache.save(trainers);
    } catch (_) {
      // A failed cache write must not hide fresh content.
    }
    return TrainersState(trainers);
  }

  Future<void> _revalidate(List<Trainer> current) async {
    try {
      final fresh = await _fetch();
      if (ref.mounted) state = AsyncData(fresh);
    } on RepositoryFailure catch (e) {
      if (ref.mounted) {
        state = AsyncData(TrainersState(current, refreshError: e));
      }
    }
  }
}

final trainersProvider = AsyncNotifierProvider<TrainersNotifier, TrainersState>(
  TrainersNotifier.new,
  // Failures are shown with a Retry button instead of retried silently.
  retry: (_, _) => null,
);

/// The trainer with [id] once content has loaded, else null.
final trainerProvider = Provider.family<Trainer?, String>(
  (ref, id) => ref
      .watch(trainersProvider)
      .value
      ?.trainers
      .where((t) => t.id == id)
      .firstOrNull,
);

/// The routine with [id] once content has loaded, else null.
final routineProvider = Provider.family<Routine?, String>(
  (ref, id) => ref
      .watch(trainersProvider)
      .value
      ?.trainers
      .expand((t) => t.routines)
      .where((r) => r.id == id)
      .firstOrNull,
);
