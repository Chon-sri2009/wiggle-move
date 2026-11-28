import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wiggle_move/features/playlist/playlist_store.dart';
import 'package:wiggle_move/shared/backend/leaderboard_repository.dart';
import 'package:wiggle_move/shared/backend/offline_leaderboard_repository.dart';
import 'package:wiggle_move/shared/prefs.dart';

void main() {
  group('PlaylistsNotifier', () {
    Future<ProviderContainer> makeContainer() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      return ProviderContainer(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      );
    }

    test('starts with a default mix and persists CRUD + reorder', () async {
      final c = await makeContainer();
      addTearDown(c.dispose);

      final initial = c.read(playlistsProvider);
      expect(initial, isNotEmpty);
      expect(initial.first.routineIds, contains('video-squat-demo'));

      final notifier = c.read(playlistsProvider.notifier);
      final created = await notifier.create(
        'Morning Burn',
        routineIds: ['pop-starter', 'squat-sets'],
      );
      await notifier.addRoutine(created.id, 'cardio-burn');
      await notifier.rename(created.id, 'Morning Cardio');
      await notifier.reorderRoutine(created.id, 0, 2);

      final updated = c
          .read(playlistsProvider)
          .firstWhere((p) => p.id == created.id);
      expect(updated.name, 'Morning Cardio');
      expect(updated.routineIds, ['squat-sets', 'cardio-burn', 'pop-starter']);

      await notifier.removeRoutineAt(created.id, 1);
      expect(
        c
            .read(playlistsProvider)
            .firstWhere((p) => p.id == created.id)
            .routineIds,
        ['squat-sets', 'pop-starter'],
      );

      await notifier.delete(created.id);
      expect(
        c.read(playlistsProvider).where((p) => p.id == created.id),
        isEmpty,
      );
    });

    test('ActivePlaylistNotifier advances through queued routines', () async {
      final c = await makeContainer();
      addTearDown(c.dispose);

      const playlist = WorkoutPlaylist(
        id: 'p1',
        name: 'Test Mix',
        routineIds: ['a', 'b', 'c'],
      );
      final active = c.read(activePlaylistProvider.notifier);
      active.start(playlist);
      expect(c.read(activePlaylistProvider)!.currentRoutineId, 'a');
      expect(c.read(activePlaylistProvider)!.hasNext, isTrue);

      expect(active.advanceToNext(), 'b');
      expect(active.advanceToNext(), 'c');
      expect(c.read(activePlaylistProvider)!.hasNext, isFalse);
      expect(active.advanceToNext(), isNull);
      expect(c.read(activePlaylistProvider), isNull);
    });
  });

  group('demoLeaderboardPlays', () {
    test('populates weekly and all-time rankings when enabled', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = OfflineLeaderboardRepository(
        prefs,
        playerName: () => 'Tester',
        routineIdsIn: (_) async => {'video-squat-demo', 'squat-sets'},
        includeDemoPlayers: true,
        now: () => DateTime.utc(2026, 11, 25, 12),
      );
      final weekly = await repo.fetch(period: LeaderboardPeriod.week);
      final squatOnly = await repo.fetch(
        routineId: 'video-squat-demo',
        period: LeaderboardPeriod.all,
      );
      expect(weekly.length, greaterThanOrEqualTo(8));
      expect(squatOnly.length, greaterThanOrEqualTo(8));
      expect(weekly.first.rank, 1);
    });
  });
}
