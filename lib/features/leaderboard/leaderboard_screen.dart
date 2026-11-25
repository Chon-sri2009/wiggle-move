import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/backend/auth_providers.dart';
import '../../shared/widgets/async_states.dart';
import '../trainers/trainer_data.dart';
import 'leaderboard_store.dart';

class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  String? _routineId;

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(leaderboardProvider);
    final me = ref.watch(authUserProvider)?.displayName;
    final ranked = rankEntries(entries, routineId: _routineId);
    final routines = trainers.expand((t) => t.routines).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Leaderboard')),
      body: Column(
        children: [
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
            child: ranked.isEmpty
                ? const EmptyView(
                    message:
                        'No scores yet. Finish a routine to get on the board!',
                  )
                : ListView.builder(
                    itemCount: ranked.length,
                    itemBuilder: (context, i) {
                      final e = ranked[i];
                      return ListTile(
                        selected: e.playerName == me,
                        leading: CircleAvatar(child: Text('${i + 1}')),
                        title: Text(e.playerName),
                        subtitle: Text(
                          routineById(e.routineId)?.name ?? e.routineId,
                        ),
                        trailing: Text(
                          '${e.score}',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
