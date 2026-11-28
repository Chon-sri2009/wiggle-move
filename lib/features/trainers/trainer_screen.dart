import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/backend/content_models.dart';
import '../../shared/backend/profile.dart';
import '../home/home_screen.dart' show TrainerAvatar;
import '../profile/profile_store.dart';
import 'personalization.dart';
import '../../shared/widgets/content_width.dart';
import '../../shared/l10n/app_language.dart';

class TrainerScreen extends ConsumerWidget {
  const TrainerScreen({super.key, required this.trainer});
  final Trainer trainer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profile = ref.watch(profileProvider).value ?? const Profile();
    return Scaffold(
      appBar: AppBar(
        title: Text(trainer.name),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TrainerAvatar(trainer: trainer, radius: 18),
          ),
        ],
      ),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              trainer.style,
              style: theme.textTheme.titleMedium?.copyWith(
                color: AppColors.accentDeep,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            for (final routine in rankRoutines(trainer.routines, profile))
              AppCard(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  title: Text(
                    routine.name,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    '${context.tr(routine.level)} · '
                    '${context.trCount('1 move', '{n} moves', routine.moves.length)} · '
                    '${routine.sets > 1 ? '${context.tr('{n} sets', {'n': routine.sets})} · ' : ''}'
                    '${context.durationLabel(routine.totalDurationMs)}'
                    '${isRecommended(routine, profile) ? context.tr(' · Recommended') : ''}',
                  ),
                  trailing: const Icon(
                    Icons.play_circle_outline,
                    size: IconSize.xl,
                    color: AppColors.primary,
                  ),
                  onTap: () => context.push('/workout/${routine.id}'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
