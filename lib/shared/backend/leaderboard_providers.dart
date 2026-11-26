import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../env.dart';
import '../prefs.dart';
import 'auth_providers.dart';
import 'leaderboard_repository.dart';
import 'offline_leaderboard_repository.dart';
import 'supabase_leaderboard_repository.dart';

/// Plays stored on this device under WM_OFFLINE, the `leaderboard` database
/// function otherwise. Tests override this with a fake.
final leaderboardRepositoryProvider = Provider<LeaderboardRepository>((ref) {
  if (Env.offline) {
    return OfflineLeaderboardRepository(
      ref.watch(sharedPrefsProvider),
      playerName: () => ref.read(authUserProvider)?.displayName,
    );
  }
  return SupabaseLeaderboardRepository(Supabase.instance.client);
});
