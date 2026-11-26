import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/backend/auth_providers.dart';
import '../../shared/backend/content_models.dart';
import '../../shared/backend/history_providers.dart';
import '../../shared/backend/history_repository.dart';
import '../../shared/backend/sessions_providers.dart';
import '../../shared/pose/pose_math.dart';
import '../scoring/move_scorer.dart';
import '../workout/workout_session.dart';

/// The signed-in user's recent plays. Refetches when the user changes or one
/// of this run's plays reaches `saved`, so a just-finished play is listed.
final historyProvider = FutureProvider.autoDispose<List<HistoryEntry>>(
  retry: (_, _) => null, // the screen offers Retry
  (ref) {
    ref.watch(authUserProvider.select((u) => u?.id));
    ref.watch(
      submissionStatusProvider.select(
        (all) =>
            all.values.where((s) => s.status == SubmissionStatus.saved).length,
      ),
    );
    return ref.watch(historyRepositoryProvider).fetch();
  },
);

/// Rebuilds the summary of a stored play against [routine], or null when it
/// cannot be shown faithfully (no per-move results, or the routine's moves
/// changed since the play).
SessionSummary? summaryFromHistory(HistoryEntry entry, Routine routine) {
  final results = entry.results;
  if (results.isEmpty || results.length != routine.moves.length) return null;
  final joints = Joint.values.asNameMap();
  final outcomes = <MoveOutcome>[];
  for (final (i, r) in results.indexed) {
    if (r.moveIdx != i) return null;
    final joint = r.worstJoint == null ? null : joints[r.worstJoint];
    outcomes.add(
      MoveOutcome(
        routine.moves[i],
        MoveResult(
          score: r.score,
          // Frames are not stored: a move with no score and no worst joint
          // is the "never visible" case.
          frames: r.score == 0 && joint == null ? 0 : 1,
          worstJoint: joint,
          worstSignedDeviation: joint == null ? null : r.deviation,
        ),
      ),
    );
  }
  return SessionSummary(routine: routine, outcomes: outcomes);
}
