import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../shared/backend/content_models.dart';
import '../../shared/l10n/app_language.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/content_width.dart';
import '../../shared/widgets/primary_button.dart';
import '../trainers/trainers_provider.dart';
import 'playlist_store.dart';

Map<String, Routine> _routineIndex(WidgetRef ref) {
  final trainers = ref.watch(trainersProvider).value?.trainers ?? const [];
  return {
    for (final t in trainers)
      for (final r in t.routines) r.id: r,
  };
}

List<({Trainer trainer, Routine routine})> _allRoutines(WidgetRef ref) {
  final trainers = ref.watch(trainersProvider).value?.trainers ?? const [];
  return [
    for (final t in trainers)
      for (final r in t.routines) (trainer: t, routine: r),
  ];
}

Future<String?> _promptPlaylistName(
  BuildContext context, {
  required String title,
  String initial = '',
  required String actionLabel,
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.tr(title)),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 40,
        decoration: InputDecoration(hintText: context.tr('Playlist name')),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: Text(context.tr(actionLabel)),
        ),
      ],
    ),
  );
  controller.dispose();
  return result?.trim().isEmpty ?? true ? null : result!.trim();
}

/// Bottom sheet letting the user add [routine] to an existing or new playlist.
Future<void> showAddToPlaylistSheet(
  BuildContext context,
  WidgetRef ref,
  Routine routine,
) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => Consumer(
      builder: (context, ref, _) {
        final playlists = ref.watch(playlistsProvider);
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  context.tr('Add to playlist'),
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              ListTile(
                leading: const Icon(
                  Icons.add_circle_outline,
                  color: AppColors.primary,
                ),
                title: Text(context.tr('New playlist')),
                onTap: () async {
                  final name = await _promptPlaylistName(
                    context,
                    title: 'New playlist',
                    actionLabel: 'Create',
                  );
                  if (name == null) return;
                  await ref
                      .read(playlistsProvider.notifier)
                      .create(name, routineIds: [routine.id]);
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          context.tr('Added to {name}', {'name': name}),
                        ),
                      ),
                    );
                  }
                },
              ),
              const Divider(),
              for (final p in playlists)
                ListTile(
                  leading: const Icon(Icons.playlist_play),
                  title: Text(p.name),
                  subtitle: Text(
                    context.trCount(
                      '1 routine',
                      '{n} routines',
                      p.routineIds.length,
                    ),
                  ),
                  onTap: () async {
                    await ref
                        .read(playlistsProvider.notifier)
                        .addRoutine(p.id, routine.id);
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            context.tr('Added to {name}', {'name': p.name}),
                          ),
                        ),
                      );
                    }
                  },
                ),
            ],
          ),
        );
      },
    ),
  );
}

class PlaylistsScreen extends ConsumerWidget {
  const PlaylistsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final playlists = ref.watch(playlistsProvider);
    final byId = _routineIndex(ref);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Playlists'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final name = await _promptPlaylistName(
            context,
            title: 'New playlist',
            actionLabel: 'Create',
          );
          if (name == null) return;
          final created = await ref
              .read(playlistsProvider.notifier)
              .create(name);
          if (context.mounted) {
            context.push('/playlists/${created.id}');
          }
        },
        icon: const Icon(Icons.add),
        label: Text(context.tr('New playlist')),
      ),
      body: ContentWidth(
        child: playlists.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    context.tr(
                      'No playlists yet — create one to queue workouts',
                    ),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 96),
                children: [
                  for (final p in playlists)
                    () {
                      final totalMs = p.routineIds.fold<int>(
                        0,
                        (sum, id) => sum + (byId[id]?.totalDurationMs ?? 0),
                      );
                      final playable = [
                        for (final id in p.routineIds)
                          if (byId.containsKey(id)) id,
                      ];
                      return AppCard(
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          leading: CircleAvatar(
                            backgroundColor: AppColors.primary.withValues(
                              alpha: 0.14,
                            ),
                            foregroundColor: AppColors.primary,
                            child: const Icon(Icons.playlist_play),
                          ),
                          title: Text(
                            p.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            '${context.trCount('1 routine', '{n} routines', p.routineIds.length)}'
                            '${totalMs > 0 ? ' · ${context.durationLabel(totalMs)}' : ''}',
                          ),
                          trailing: playable.isEmpty
                              ? const Icon(Icons.chevron_right)
                              : IconButton(
                                  tooltip: context.tr('Start playlist'),
                                  icon: const Icon(
                                    Icons.play_circle_filled,
                                    size: IconSize.xl,
                                    color: AppColors.primary,
                                  ),
                                  onPressed: () {
                                    final clean = p.copyWith(
                                      routineIds: playable,
                                    );
                                    ref
                                        .read(activePlaylistProvider.notifier)
                                        .start(clean);
                                    context.push('/workout/${playable.first}');
                                  },
                                ),
                          onTap: () => context.push('/playlists/${p.id}'),
                        ),
                      );
                    }(),
                ],
              ),
      ),
    );
  }
}

class PlaylistDetailScreen extends ConsumerWidget {
  const PlaylistDetailScreen({super.key, required this.playlistId});
  final String playlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final playlists = ref.watch(playlistsProvider);
    final playlist = playlists.where((p) => p.id == playlistId).firstOrNull;
    if (playlist == null) {
      return Scaffold(
        appBar: AppBar(title: Text(context.tr('Playlists'))),
        body: Center(child: Text(context.tr('Playlist not found'))),
      );
    }

    final byId = _routineIndex(ref);
    final all = _allRoutines(ref);
    final playable = [
      for (final id in playlist.routineIds)
        if (byId.containsKey(id)) id,
    ];
    final totalMs = playable.fold<int>(
      0,
      (sum, id) => sum + (byId[id]?.totalDurationMs ?? 0),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(playlist.name),
        actions: [
          IconButton(
            tooltip: context.tr('Rename'),
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final next = await _promptPlaylistName(
                context,
                title: 'Rename playlist',
                initial: playlist.name,
                actionLabel: 'Save',
              );
              if (next != null) {
                await ref
                    .read(playlistsProvider.notifier)
                    .rename(playlist.id, next);
              }
            },
          ),
          IconButton(
            tooltip: context.tr('Delete'),
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              await ref.read(playlistsProvider.notifier).delete(playlist.id);
              if (context.mounted) context.pop();
            },
          ),
        ],
      ),
      body: ContentWidth(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${context.trCount('1 routine', '{n} routines', playlist.routineIds.length)}'
                    '${totalMs > 0 ? ' · ${context.durationLabel(totalMs)}' : ''}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.accentDeep,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: PrimaryButton(
                          label: 'Start playlist',
                          onPressed: playable.isEmpty
                              ? null
                              : () {
                                  final clean = playlist.copyWith(
                                    routineIds: playable,
                                  );
                                  ref
                                      .read(activePlaylistProvider.notifier)
                                      .start(clean);
                                  context.push('/workout/${playable.first}');
                                },
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: () =>
                            _pickRoutineSheet(context, ref, playlist.id, all),
                        icon: const Icon(Icons.add),
                        label: Text(context.tr('Add workout')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: playlist.routineIds.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          context.tr('Add workouts to build your playlist'),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      itemCount: playlist.routineIds.length,
                      onReorderItem: (oldIndex, newIndex) => ref
                          .read(playlistsProvider.notifier)
                          .reorderRoutine(playlist.id, oldIndex, newIndex),
                      itemBuilder: (context, index) {
                        final id = playlist.routineIds[index];
                        final routine = byId[id];
                        return Card(
                          key: ValueKey('$id-$index'),
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor: AppColors.primary.withValues(
                                alpha: 0.14,
                              ),
                              foregroundColor: AppColors.primary,
                              child: Text('${index + 1}'),
                            ),
                            title: Text(
                              routine?.name ?? id,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: routine == null
                                ? null
                                : Text(
                                    '${context.tr(routine.level)} · '
                                    '${context.durationLabel(routine.totalDurationMs)}',
                                  ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: context.tr('Remove'),
                                  icon: const Icon(Icons.close),
                                  onPressed: () => ref
                                      .read(playlistsProvider.notifier)
                                      .removeRoutineAt(playlist.id, index),
                                ),
                                ReorderableDragStartListener(
                                  index: index,
                                  child: const Icon(Icons.drag_handle),
                                ),
                              ],
                            ),
                            onTap: routine == null
                                ? null
                                : () {
                                    ref
                                        .read(activePlaylistProvider.notifier)
                                        .start(playlist, startIndex: index);
                                    context.push('/workout/${routine.id}');
                                  },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickRoutineSheet(
    BuildContext context,
    WidgetRef ref,
    String playlistId,
    List<({Trainer trainer, Routine routine})> all,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                context.tr('Add workout'),
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            for (final item in all)
              ListTile(
                title: Text(item.routine.name),
                subtitle: Text(
                  '${item.trainer.name} · ${context.tr(item.routine.level)} · '
                  '${context.durationLabel(item.routine.totalDurationMs)}',
                ),
                trailing: const Icon(Icons.add_circle_outline),
                onTap: () async {
                  await ref
                      .read(playlistsProvider.notifier)
                      .addRoutine(playlistId, item.routine.id);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }
}
