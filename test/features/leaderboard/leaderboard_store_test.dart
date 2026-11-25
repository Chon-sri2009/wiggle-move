import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wiggle_move/features/leaderboard/leaderboard_store.dart';
import 'package:wiggle_move/shared/backend/auth_providers.dart';
import 'package:wiggle_move/shared/backend/offline_sessions_repository.dart';
import 'package:wiggle_move/shared/backend/sessions_providers.dart';
import 'package:wiggle_move/shared/backend/sessions_repository.dart';
import 'package:wiggle_move/shared/prefs.dart';

import '../../support/fakes.dart';

void main() {
  test('WM_OFFLINE: a submitted play shows on the local leaderboard', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(FakeAuthRepository.ann),
        ),
        sessionsRepositoryProvider.overrideWithValue(
          OfflineSessionsRepository(prefs, playerName: () => 'Ann'),
        ),
      ],
    );
    addTearDown(c.dispose);
    // Read before the play, like the leaderboard screen would.
    expect(c.read(leaderboardProvider), isEmpty);

    final outcome = await c
        .read(sessionSyncProvider)
        .submit(
          SessionSubmission(
            routineId: 'mia-pop',
            clientNonce: '00000000-0000-4000-8000-000000000001',
            durationMs: 24000,
            score: 77,
            playedAt: DateTime.utc(2026),
            userId: 'u1',
            results: const [MoveSubmission(moveIdx: 0, score: 77)],
          ),
        );
    expect(outcome, isA<SubmitSaved>());
    final entries = c.read(leaderboardProvider);
    expect(entries.single.playerName, 'Ann');
    expect(entries.single.score, 77);
    expect(entries.single.routineId, 'mia-pop');
  });
}
