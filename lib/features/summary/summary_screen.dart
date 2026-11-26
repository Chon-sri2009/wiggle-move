import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../shared/backend/sessions_providers.dart';
import '../../shared/backend/sessions_repository.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/primary_button.dart';
import '../scoring/move_scorer.dart';
import '../workout/workout_session.dart';

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

class SummaryScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = summary.totalScore;
    return Scaffold(
      appBar: AppBar(
        title: Text(fromHistory ? 'Past session' : 'Session summary'),
        automaticallyImplyLeading: fromHistory,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Column(
              children: [
                Text(summary.routine.name, style: theme.textTheme.titleMedium),
                Text(
                  '$total',
                  style: theme.textTheme.displayLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.accent,
                  ),
                ),
                Text(_grade(total), style: theme.textTheme.titleLarge),
                if (submissionId case final id?) _UploadStatus(id),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('Move by move', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final outcome in summary.outcomes) _MoveCard(outcome),
          const SizedBox(height: 16),
          PrimaryButton(
            onPressed: () => context.go('/leaderboard'),
            label: 'See leaderboard',
          ),
          TextButton(
            onPressed: () => context.go('/'),
            child: const Text('Back to trainers'),
          ),
        ],
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
        Colors.green,
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
  const _MoveCard(this.outcome);
  final MoveOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = outcome.result;
    final color = result.score >= 80
        ? Colors.green
        : (result.score >= 50 ? Colors.orange : Colors.red);
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
                '${result.score}',
                style: theme.textTheme.titleLarge?.copyWith(color: color),
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
          Text(_feedback(result), style: theme.textTheme.bodyMedium),
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
