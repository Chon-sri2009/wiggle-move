import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../scoring/move_scorer.dart';
import '../workout/workout_session.dart';

class SummaryScreen extends StatelessWidget {
  const SummaryScreen({super.key, required this.summary});
  final SessionSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = summary.totalScore;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Session summary'),
        automaticallyImplyLeading: false,
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
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('Move by move', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final outcome in summary.outcomes) _MoveCard(outcome),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => context.go('/leaderboard'),
            child: const Text('See leaderboard'),
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
    return Card(
      child: Padding(
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
