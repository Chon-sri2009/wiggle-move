import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/backend/content_models.dart';
import '../../shared/backend/leaderboard_repository.dart';
import '../../shared/backend/profile_repository.dart';
import '../../shared/widgets/async_states.dart';
import '../trainers/trainers_provider.dart';
import 'leaderboard_provider.dart';

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
      appBar: AppBar(title: const Text('Leaderboard')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: SegmentedButton<LeaderboardPeriod>(
              segments: const [
                ButtonSegment(
                  value: LeaderboardPeriod.week,
                  label: Text('Weekly'),
                ),
                ButtonSegment(
                  value: LeaderboardPeriod.all,
                  label: Text('All-time'),
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
                  label: const Text('All types'),
                  selected: _category == null,
                  onSelected: (_) => _pickCategory(null),
                ),
                ChoiceChip(
                  label: const Text('Dance'),
                  selected: _category == Routine.dance,
                  onSelected: (_) => _pickCategory(Routine.dance),
                ),
                ChoiceChip(
                  label: const Text('Cardio'),
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
                  label: const Text('All'),
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
                        itemCount: rows.length,
                        itemBuilder: (context, i) => _RowTile(rows[i]),
                      ),
              ),
            ),
          ),
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
    final scheme = Theme.of(context).colorScheme;
    final initial = row.displayName.isEmpty
        ? '?'
        : row.displayName.characters.first.toUpperCase();
    return ListTile(
      selected: row.isMe,
      selectedTileColor: scheme.primaryContainer.withValues(alpha: 0.5),
      leading: SizedBox(
        width: 72,
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '${row.rank}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            CircleAvatar(child: Text(initial)),
          ],
        ),
      ),
      title: Text(row.isMe ? '${row.displayName} (you)' : row.displayName),
      trailing: Text(
        '${row.score}',
        style: Theme.of(context).textTheme.titleLarge,
      ),
    );
  }
}
