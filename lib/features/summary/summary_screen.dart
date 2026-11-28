import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../shared/backend/sessions_providers.dart';
import '../../shared/backend/sessions_repository.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/primary_button.dart';
import '../playlist/playlist_store.dart';
import '../scoring/move_scorer.dart';
import '../trainers/trainers_provider.dart';
import '../workout/workout_session.dart';
import '../../shared/widgets/content_width.dart';
import '../../shared/l10n/app_language.dart';

/// Route extra for `/summary`: the play and its upload id (client nonce),
/// null when nothing was submitted (signed out).
class SummaryArgs {
  const SummaryArgs(
    this.summary, {
    this.submissionId,
    this.fromHistory = false,
  });
  final SessionSummary summary;
  final String? submissionId;

  /// Opened from the history list: shows a back arrow, not a fresh result.
  final bool fromHistory;
}

class SummaryScreen extends ConsumerWidget {
  const SummaryScreen({
    super.key,
    required this.summary,
    this.submissionId,
    this.fromHistory = false,
  });
  final SessionSummary summary;
  final bool fromHistory;

  /// Client nonce of the submitted play; its upload status is shown.
  final String? submissionId;

  static const savingText = 'Saving your score…';
  static const savedText = 'Saved';
  static const queuedText = "Will upload when you're back online";

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final total = summary.totalScore;
    final activePlaylist = fromHistory
        ? null
        : ref.watch(activePlaylistProvider);
    final matchesPlaylist =
        activePlaylist != null &&
        activePlaylist.currentRoutineId == summary.routine.id;
    final nextRoutineId = matchesPlaylist ? activePlaylist.nextRoutineId : null;
    final nextRoutineName = nextRoutineId == null
        ? null
        : ref
              .watch(trainersProvider)
              .value
              ?.trainers
              .expand((t) => t.routines)
              .where((r) => r.id == nextRoutineId)
              .firstOrNull
              ?.name;
    return Scaffold(
      appBar: AppBar(
        title: Text(fromHistory ? 'Past session' : 'Session summary'),
        automaticallyImplyLeading: fromHistory,
      ),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AppCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(
                    context.tr('Results'),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    summary.routine.name,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.tr('Score :'),
                    style: theme.textTheme.titleMedium,
                  ),
                  Text(
                    '$total',
                    style: theme.textTheme.displayLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.accentDeep,
                    ),
                  ),
                  Text(
                    context.tr(_grade(total)),
                    style: theme.textTheme.titleLarge,
                  ),
                  _Stats(summary),
                  if (submissionId case final id?) _UploadStatus(id),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              context.tr('Move by move'),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final outcome in summary.outcomes)
              _MoveCard(outcome, summary.routine.sets),
            const SizedBox(height: 16),
            if (matchesPlaylist) ...[
              AppCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${activePlaylist.playlistName} · '
                      '${activePlaylist.index + 1} / ${activePlaylist.total}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.accentDeep,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (nextRoutineId != null)
                      PrimaryButton(
                        label: nextRoutineName != null
                            ? context.tr('Next in playlist: {name}', {
                                'name': nextRoutineName,
                              })
                            : context.tr('Next in playlist'),
                        onPressed: () {
                          final next = ref
                              .read(activePlaylistProvider.notifier)
                              .advanceToNext();
                          if (next != null) {
                            context.pushReplacement('/workout/$next');
                          }
                        },
                      )
                    else
                      Text(
                        context.tr('Playlist complete!'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: AppColors.success,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            PrimaryButton(
              onPressed: () {
                ref.read(activePlaylistProvider.notifier).clear();
                context.go('/leaderboard');
              },
              label: 'See leaderboard',
            ),
            TextButton(
              onPressed: () {
                ref.read(activePlaylistProvider.notifier).clear();
                context.go('/');
              },
              child: Text(context.tr('Back to trainers')),
            ),
          ],
        ),
      ),
    );
  }

  static String _grade(int score) {
    if (score >= 90) return 'Perfect groove!';
    if (score >= 70) return 'Great moves!';
    if (score >= 50) return 'Getting there';
    return 'Keep practicing';
  }
}

/// Sets, reps and an energy estimate under the grade (only what applies).
class _Stats extends StatelessWidget {
  const _Stats(this.summary);
  final SessionSummary summary;

  @override
  Widget build(BuildContext context) {
    final kcal = summary.calories;
    final ms = summary.durationMs;
    final parts = [
      if (summary.routine.sets > 1)
        context.tr('{n} sets', {'n': summary.routine.sets}),
      if (summary.targetReps > 0)
        context.tr('{a} / {b} reps', {
          'a': summary.totalReps,
          'b': summary.targetReps,
        }),
      if (ms != null && ms > 0)
        context.tr('{t} active', {'t': _minutesSeconds(ms)}),
      if (kcal != null && kcal > 0)
        context.tr('≈ {n} kcal (estimate)', {'n': kcal}),
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        parts.join(' · '),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

String _minutesSeconds(int ms) {
  final s = (ms / 1000).round();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// One line under the score; never blocks the summary.
class _UploadStatus extends ConsumerWidget {
  const _UploadStatus(this.id);
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(submissionStatusProvider.select((m) => m[id]));
    if (state == null) return const SizedBox.shrink();
    final (icon, text, color) = switch (state.status) {
      SubmissionStatus.pending => (
        Icons.cloud_upload_outlined,
        SummaryScreen.savingText,
        null,
      ),
      SubmissionStatus.saved => (
        Icons.cloud_done_outlined,
        SummaryScreen.savedText,
        AppColors.success,
      ),
      SubmissionStatus.queued => (
        Icons.cloud_off_outlined,
        SummaryScreen.queuedText,
        null,
      ),
      SubmissionStatus.rejected => (
        Icons.error_outline,
        state.message ?? SubmitRejected.invalid,
        Theme.of(context).colorScheme.error,
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _MoveCard extends StatelessWidget {
  const _MoveCard(this.outcome, this.sets);
  final MoveOutcome outcome;

  /// Sets played: the reps target of a move is per set.
  final int sets;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = outcome.result;
    final (color, level) = result.score >= 80
        ? (AppColors.success, 'Great')
        : (result.score >= 50
              ? (AppColors.warning, 'OK')
              : (AppColors.danger, 'Needs work'));
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  outcome.move.name,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Text(
                '${result.score} · ${context.tr(level)}',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: result.score / 100,
            color: color,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
          const SizedBox(height: 8),
          if (outcome.move.rep case final rep?) ...[
            Text(
              context.tr('Reps {a} / {b}', {
                'a': result.reps,
                'b': rep.target * sets,
              }),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
          ],
          Text(
            context.tr(_feedback(result)),
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  static String _feedback(MoveResult r) {
    if (!r.wasVisible) {
      return 'We could not see you for this move. Step back so your whole body is in frame.';
    }
    final joint = r.worstJoint;
    if (joint == null) return 'Nice — your form matched the trainer.';
    final off = r.worstSignedDeviation!;
    final hint = joint.hint(off > 0);
    return 'Your ${joint.label} was about ${off.abs().round()}° off. Try to $hint.';
  }
}
