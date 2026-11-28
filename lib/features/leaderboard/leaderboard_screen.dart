import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../shared/backend/content_models.dart';
import '../../shared/backend/leaderboard_repository.dart';
import '../../shared/backend/profile_repository.dart';
import '../../shared/widgets/async_states.dart';
import '../trainers/trainers_provider.dart';
import 'leaderboard_provider.dart';
import '../../shared/widgets/content_width.dart';
import '../../shared/l10n/app_language.dart';

class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  String? _routineId;
  String? _category;
  LeaderboardPeriod _period = LeaderboardPeriod.all;

  LeaderboardQuery get _query =>
      (routineId: _routineId, period: _period, category: _category);

  void _pickCategory(String? category) => setState(() {
    _category = category;
    // The routine chips only offer this category's routines.
    _routineId = null;
  });

  Future<void> _refresh() async {
    final provider = leaderboardProvider(_query);
    ref.invalidate(provider);
    try {
      await ref.read(provider.future);
    } catch (_) {
      // Shown as the error state.
    }
  }

  @override
  Widget build(BuildContext context) {
    final board = ref.watch(leaderboardProvider(_query));
    // Content may still be loading: routine chips appear once it is there.
    final routines = [
      for (final t in ref.watch(trainersProvider).value?.trainers ?? const [])
        for (final r in t.routines)
          if (_category == null || r.category == _category) r,
    ];

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('LeaderBoard'))),
      body: ContentWidth(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: SegmentedButton<LeaderboardPeriod>(
                segments: [
                  ButtonSegment(
                    value: LeaderboardPeriod.week,
                    label: Text(context.tr('Weekly')),
                  ),
                  ButtonSegment(
                    value: LeaderboardPeriod.all,
                    label: Text(context.tr('All-time')),
                  ),
                ],
                selected: {_period},
                onSelectionChanged: (s) => setState(() => _period = s.first),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Row(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: Text(context.tr('All types')),
                    selected: _category == null,
                    onSelected: (_) => _pickCategory(null),
                  ),
                  ChoiceChip(
                    label: Text(context.tr('Dance')),
                    selected: _category == Routine.dance,
                    onSelected: (_) => _pickCategory(Routine.dance),
                  ),
                  ChoiceChip(
                    label: Text(context.tr('Cardio')),
                    selected: _category == Routine.cardio,
                    onSelected: (_) => _pickCategory(Routine.cardio),
                  ),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(12),
              child: Row(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: Text(context.tr('All')),
                    selected: _routineId == null,
                    onSelected: (_) => setState(() => _routineId = null),
                  ),
                  for (final r in routines)
                    ChoiceChip(
                      label: Text(r.name),
                      selected: _routineId == r.id,
                      onSelected: (_) => setState(() => _routineId = r.id),
                    ),
                ],
              ),
            ),
            Expanded(
              child: board.when(
                skipLoadingOnReload: true,
                loading: () => const LoadingView(),
                error: (e, _) => ErrorView(
                  message: e is RepositoryFailure
                      ? e.message
                      : 'Could not load the leaderboard.',
                  onRetry: _refresh,
                ),
                data: (rows) => RefreshIndicator(
                  onRefresh: _refresh,
                  child: rows.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 120),
                            EmptyView(
                              message: 'No scores yet — play a routine',
                              icon: Icons.emoji_events_outlined,
                            ),
                          ],
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: rows.length + 1,
                          itemBuilder: (context, i) => i == 0
                              ? const _HeaderRow()
                              : _RowTile(rows[i - 1]),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Orange "Rank / Name / Score" pill above the rows.
class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(color: Colors.white, fontWeight: FontWeight.w700);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: AppColors.accentDeep,
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      child: Row(
        children: [
          SizedBox(width: 48, child: Text(context.tr('Rank'), style: style)),
          Expanded(child: Text(context.tr('Name'), style: style)),
          Text(context.tr('Score'), style: style),
        ],
      ),
    );
  }
}

class _RowTile extends StatelessWidget {
  const _RowTile(this.row);
  final LeaderboardRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = row.displayName.isEmpty
        ? '?'
        : row.displayName.characters.first.toUpperCase();
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: row.isMe ? AppColors.accent.withValues(alpha: 0.18) : null,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        dense: true,
        selected: row.isMe,
        selectedColor: AppColors.primary,
        leading: SizedBox(
          width: 80,
          child: Row(
            children: [
              SizedBox(
                width: 32,
                child: Text(
                  '${row.rank}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              CircleAvatar(
                radius: 14,
                backgroundColor: AppColors.field,
                child: Text(initial, style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
        title: Text(
          row.isMe
              ? context.tr('{name} (you)', {'name': row.displayName})
              : row.displayName,
        ),
        trailing: Text(
          '${row.score}',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
