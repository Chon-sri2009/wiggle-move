import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../home/player_name.dart';
import 'trainer.dart';

class TrainerScreen extends ConsumerWidget {
  const TrainerScreen({super.key, required this.trainer});
  final Trainer trainer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(trainer.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(trainer.style, style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          for (final routine in trainer.routines)
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                title: Text(routine.name, style: theme.textTheme.titleLarge),
                subtitle: Text(
                  '${routine.level} · ${routine.moves.length} moves · '
                  '${(routine.durationMs / 1000).round()}s',
                ),
                trailing: const Icon(Icons.play_circle_fill, size: 36),
                onTap: () async {
                  final name = await ensurePlayerName(context, ref);
                  if (name != null && context.mounted) {
                    context.push('/workout/${routine.id}');
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}
