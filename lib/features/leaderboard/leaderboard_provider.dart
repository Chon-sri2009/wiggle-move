import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/backend/auth_providers.dart';
import '../../shared/backend/leaderboard_providers.dart';
import '../../shared/backend/leaderboard_repository.dart';
import '../../shared/backend/sessions_providers.dart';

/// What the leaderboard shows: one routine (null = global) in one period,
/// optionally only routines of a category (null = all).
typedef LeaderboardQuery = ({
  String? routineId,
  LeaderboardPeriod period,
  String? category,
});

/// Rows for [query]. One provider per query, so a slow response for an
/// earlier selection can never replace the one now on screen. Refetches
/// when the signed-in user changes (the "you" row) and when one of this
/// run's plays finishes uploading (so a just-played score appears).
final leaderboardProvider = FutureProvider.autoDispose
    .family<List<LeaderboardRow>, LeaderboardQuery>(
      retry: (_, _) => null, // the screen offers Retry
      (ref, query) {
        ref.watch(authUserProvider.select((u) => u?.id));
        ref.watch(
          submissionStatusProvider.select(
            (all) => all.values
                .where((s) => s.status == SubmissionStatus.saved)
                .length,
          ),
        );
        return ref
            .watch(leaderboardRepositoryProvider)
            .fetch(
              routineId: query.routineId,
              period: query.period,
              category: query.category,
            );
      },
    );
