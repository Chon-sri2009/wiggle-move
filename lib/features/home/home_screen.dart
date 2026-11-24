import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../trainers/trainer_data.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wiggle Move'),
        actions: [
          IconButton(
            tooltip: 'Leaderboard',
            icon: const Icon(Icons.emoji_events),
            onPressed: () => context.push('/leaderboard'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Choose your trainer', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 12),
          for (final trainer in trainers)
            Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: CircleAvatar(
                  radius: 28,
                  backgroundColor: trainer.color,
                  child: Text(
                    trainer.name.split(' ').last[0],
                    style: const TextStyle(color: Colors.white, fontSize: 24),
                  ),
                ),
                title: Text(trainer.name, style: theme.textTheme.titleLarge),
                subtitle: Text(
                  '${trainer.style} · ${trainer.routines.length} routines',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/trainer/${trainer.id}'),
              ),
            ),
        ],
      ),
    );
  }
}
