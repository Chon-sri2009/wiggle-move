import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/backend/history_repository.dart';
import '../../shared/backend/profile_repository.dart';
import '../../shared/widgets/app_snackbar.dart';
import '../../shared/widgets/async_states.dart';
import '../summary/summary_screen.dart';
import '../trainers/trainers_provider.dart';
import 'history_provider.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  static const emptyText = 'No plays yet — finish a routine to see it here';
  static const unavailableText =
      'Details for this play are not available any more.';

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(historyProvider);
    try {
      await ref.read(historyProvider.future);
    } catch (_) {
      // Shown as the error state.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: history.when(
        skipLoadingOnReload: true,
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: e is RepositoryFailure
              ? e.message
              : RepositoryFailure.generic,
          onRetry: () => _refresh(ref),
        ),
        data: (entries) => RefreshIndicator(
          onRefresh: () => _refresh(ref),
          child: entries.isEmpty
              ? ListView(
                  children: const [
                    SizedBox(height: 120),
                    EmptyView(message: emptyText, icon: Icons.history),
                  ],
                )
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: entries.length,
                  itemBuilder: (context, i) => _EntryTile(entries[i]),
                ),
        ),
      ),
    );
  }
}

class _EntryTile extends ConsumerWidget {
  const _EntryTile(this.entry);
  final HistoryEntry entry;

  void _open(BuildContext context, WidgetRef ref) {
    final routine = ref.read(routineProvider(entry.routineId));
    final summary = routine == null ? null : summaryFromHistory(entry, routine);
    if (summary == null) {
      showAppSnackBar(context, HistoryScreen.unavailableText);
      return;
    }
    context.push('/summary', extra: SummaryArgs(summary, fromHistory: true));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name =
        ref.watch(routineProvider(entry.routineId))?.name ?? entry.routineId;
    return ListTile(
      title: Text(name),
      subtitle: Text(formatPlayedAt(entry.playedAt)),
      trailing: Text(
        '${entry.score}',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      onTap: () => _open(context, ref),
    );
  }
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// e.g. `Nov 26, 2026 · 14:05` in the device's time zone.
String formatPlayedAt(DateTime at) {
  final t = at.toLocal();
  final hh = t.hour.toString().padLeft(2, '0');
  final mm = t.minute.toString().padLeft(2, '0');
  return '${_months[t.month - 1]} ${t.day}, ${t.year} · $hh:$mm';
}
