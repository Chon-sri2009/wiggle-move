import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/backend/auth_providers.dart';
import '../../shared/backend/content_models.dart';
import '../../shared/widgets/async_states.dart';
import '../../shared/backend/profile.dart';
import '../../shared/backend/trainer_photo.dart';
import '../profile/profile_store.dart';
import '../trainers/content_gate.dart';
import '../trainers/personalization.dart';
import '../trainers/trainers_provider.dart';
import '../../shared/widgets/content_width.dart';
import '../../shared/l10n/app_language.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final name = ref.watch(authUserProvider)?.displayName ?? '';
    final content = ref.watch(trainersProvider);
    // Home is only reachable once the profile loaded; default = no ranking.
    final profile = ref.watch(profileProvider).value ?? const Profile();
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'WiggleMove',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: context.tr('Profile'),
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => context.push('/profile'),
          ),
        ],
      ),
      body: ContentWidth(
        child: RefreshIndicator(
          onRefresh: () => ref.read(trainersProvider.notifier).refresh(),
          child: ListView(
            // Pull-to-refresh must work even when the list is short.
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                context.tr('Hello, {name}', {'name': name}),
                style: theme.textTheme.displaySmall?.copyWith(
                  color: AppColors.accentDeep,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                context.tr('Choose your trainer!'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              ...switch (content) {
                AsyncValue(:final value?) => [
                  if (value.isStale) const _StaleNote(),
                  for (final trainer in rankTrainers(value.trainers, profile))
                    _TrainerCard(
                      trainer: trainer,
                      recommended: trainerRecommended(trainer, profile),
                    ),
                ],
                AsyncValue(:final error?) => [
                  ErrorView(
                    message: contentErrorMessage(error),
                    onRetry: () =>
                        ref.read(trainersProvider.notifier).refresh(),
                  ),
                ],
                _ => [const LoadingView()],
              },
            ],
          ),
        ),
      ),
    );
  }
}

/// Avatar letter: first character of the last word of [name], ignoring any
/// "(note)" suffix, so "Video Coach (demo)" gives "C", not "(". '?' if empty.
String trainerInitial(String name) {
  final plain = name.replaceAll(RegExp(r'\([^)]*\)'), ' ').trim();
  final words = (plain.isEmpty ? name.trim() : plain).split(RegExp(r'\s+'));
  final last = words.last;
  return last.isEmpty ? '?' : last.characters.first;
}

/// The trainer's photo from Storage; the colored initial while there is no
/// photo, offline, or when the image fails to load.
class TrainerAvatar extends StatefulWidget {
  const TrainerAvatar({super.key, required this.trainer, this.radius = 28});
  final Trainer trainer;
  final double radius;

  @override
  State<TrainerAvatar> createState() => _TrainerAvatarState();
}

class _TrainerAvatarState extends State<TrainerAvatar> {
  bool _failed = false;

  @override
  Widget build(BuildContext context) {
    final url = trainerPhotoUrl(widget.trainer.photoPath);
    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: widget.trainer.color,
      backgroundImage: url == null || _failed ? null : NetworkImage(url),
      onBackgroundImageError: url == null || _failed
          ? null
          : (_, _) => setState(() => _failed = true),
      child: url == null || _failed
          ? Text(
              trainerInitial(widget.trainer.name),
              style: TextStyle(
                color: AppColors.primary,
                fontSize: widget.radius * 0.85,
                fontWeight: FontWeight.w700,
              ),
            )
          : null,
    );
  }
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
            context.tr(
              'Couldn\'t update — showing saved content. Pull down to retry.',
            ),
            style: TextStyle(color: Theme.of(context).hintColor),
          ),
        ),
      ],
    ),
  );
}

class _TrainerCard extends StatelessWidget {
  const _TrainerCard({required this.trainer, required this.recommended});
  final Trainer trainer;
  final bool recommended;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: TrainerAvatar(trainer: trainer),
        title: Text(
          trainer.name,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          '${trainer.style} · '
          '${context.trCount('1 routine', '{n} routines', trainer.routines.length)}'
          '${recommended ? context.tr(' · Recommended') : ''}',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/trainer/${trainer.id}'),
      ),
    );
  }
}
