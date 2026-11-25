import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/backend/auth_providers.dart';
import '../../shared/backend/auth_repository.dart';
import '../../shared/widgets/app_snackbar.dart';
import '../../shared/backend/trainer_data.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final name = ref.watch(authUserProvider)?.displayName ?? '';
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
            onPressed: () => _showProfile(context, ref, name),
          ),
        ],
      ),
      body: ListView(
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
          for (final trainer in builtInTrainers)
            AppCard(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: CircleAvatar(
                  radius: 28,
                  backgroundColor: trainer.color,
                  child: Text(
                    trainer.name.split(' ').last[0],
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
            ),
        ],
      ),
    );
  }

  static Future<void> _showProfile(
    BuildContext context,
    WidgetRef ref,
    String name,
  ) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                await ref.read(authRepositoryProvider).signOut();
              } on AuthFailure catch (e) {
                if (context.mounted) {
                  showAppSnackBar(context, e.message, isError: true);
                }
              }
            },
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}
