import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_language.dart';

enum AppTab {
  home('/', Icons.home_outlined, 'Home'),
  history('/history', Icons.timer_outlined, 'History'),
  search('/search', Icons.search, 'Search'),
  leaderboard('/leaderboard', Icons.leaderboard_outlined, 'Leaderboard');

  const AppTab(this.path, this.icon, this.label);
  final String path;
  final IconData icon;
  final String label;
}

/// The orange bottom bar of the Figma frames (Home, History, Search,
/// Leaderboard). Tabs replace each other, so Back leaves the app section.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({super.key, required this.current});
  final AppTab current;

  @override
  Widget build(BuildContext context) => NavigationBar(
    selectedIndex: current.index,
    onDestinationSelected: (i) {
      final tab = AppTab.values[i];
      if (tab != current) context.go(tab.path);
    },
    destinations: [
      for (final t in AppTab.values)
        NavigationDestination(
          icon: Icon(t.icon),
          label: context.tr(t.label),
          tooltip: context.tr(t.label),
        ),
    ],
  );
}
