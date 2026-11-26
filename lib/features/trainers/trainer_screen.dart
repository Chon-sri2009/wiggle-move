import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/backend/content_models.dart';

class TrainerScreen extends StatelessWidget {
  const TrainerScreen({super.key, required this.trainer});
  final Trainer trainer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(trainer.name)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            trainer.style,
            style: theme.textTheme.titleMedium?.copyWith(
              color: AppColors.accent,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          for (final routine in trainer.routines)
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
                  '${routine.level} · ${routine.moves.length} moves · '
                  '${routine.sets > 1 ? '${routine.sets} sets · ' : ''}'
                  '${(routine.totalDurationMs / 1000).round()}s',
                ),
                trailing: const Icon(
                  Icons.play_circle_fill,
                  size: 36,
                  color: AppColors.secondary,
                ),
                onTap: () => context.push('/workout/${routine.id}'),
              ),
            ),
        ],
      ),
    );
  }
}
