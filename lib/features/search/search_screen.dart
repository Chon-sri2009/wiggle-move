import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/backend/content_models.dart';
import '../../shared/widgets/app_card.dart';
import '../trainers/trainers_provider.dart';
import '../../shared/widgets/content_width.dart';
import '../../shared/l10n/app_language.dart';

/// Routines whose name, trainer or style contains [query] (case-insensitive).
List<(Trainer, Routine)> searchRoutines(List<Trainer> trainers, String query) {
  final q = query.trim().toLowerCase();
  return [
    for (final t in trainers)
      for (final r in t.routines)
        if (q.isEmpty ||
            '${r.name} ${t.name} ${t.style}'.toLowerCase().contains(q))
          (t, r),
  ];
}

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final trainers = ref.watch(trainersProvider).value?.trainers ?? const [];
    final results = searchRoutines(trainers, _query);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Search'))),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              decoration: InputDecoration(
                hintText: context.tr('Search routines'),
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 16),
            for (final (trainer, routine) in results)
              AppCard(
                child: ListTile(
                  title: Text(routine.name),
                  subtitle: Text(
                    '${trainer.name} · ${context.tr(routine.level)}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/trainer/${trainer.id}'),
                ),
              ),
            if (results.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(child: Text(context.tr('Nothing found'))),
              ),
          ],
        ),
      ),
    );
  }
}
