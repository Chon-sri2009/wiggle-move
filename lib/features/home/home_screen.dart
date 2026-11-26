import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/backend/auth_providers.dart';
import '../../shared/backend/content_models.dart';
import '../../shared/widgets/async_states.dart';
import '../trainers/content_gate.dart';
import '../trainers/trainers_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final name = ref.watch(authUserProvider)?.displayName ?? '';
    final content = ref.watch(trainersProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'WiggleMove',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Leaderboard',
            icon: const Icon(Icons.emoji_events),
            onPressed: () => context.push('/leaderboard'),
          ),
          IconButton(
            tooltip: 'Profile',
            icon: const Icon(Icons.account_circle, size: 28),
            onPressed: () => context.push('/profile'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(trainersProvider.notifier).refresh(),
        child: ListView(
          // Pull-to-refresh must work even when the list is short.
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Hi, $name',
              style: theme.textTheme.displaySmall?.copyWith(
                color: AppColors.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              'Choose your trainer',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            ...switch (content) {
              AsyncValue(:final value?) => [
                if (value.isStale) const _StaleNote(),
                for (final trainer in value.trainers)
                  _TrainerCard(trainer: trainer),
              ],
              AsyncValue(:final error?) => [
                ErrorView(
                  message: contentErrorMessage(error),
                  onRetry: () => ref.read(trainersProvider.notifier).refresh(),
                ),
              ],
              _ => [const LoadingView()],
            },
          ],
        ),
      ),
    );
  }
}

/// Avatar letter: first character of the last word of [name], or '?'.
String trainerInitial(String name) {
  final words = name.trim().split(RegExp(r'\s+'));
  final last = words.last;
  return last.isEmpty ? '?' : last.characters.first;
}

class _StaleNote extends StatelessWidget {
  const _StaleNote();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Icon(Icons.cloud_off, size: 16, color: Theme.of(context).hintColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            "Couldn't update — showing saved content. Pull down to retry.",
            style: TextStyle(color: Theme.of(context).hintColor),
          ),
        ),
      ],
    ),
  );
}

class _TrainerCard extends StatelessWidget {
  const _TrainerCard({required this.trainer});
  final Trainer trainer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          radius: 28,
          backgroundColor: trainer.color,
          child: Text(
            trainerInitial(trainer.name),
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        title: Text(
          trainer.name,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          '${trainer.style} · ${trainer.routines.length} routines',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/trainer/${trainer.id}'),
      ),
    );
  }
}
