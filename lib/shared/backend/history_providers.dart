import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../env.dart';
import '../prefs.dart';
import 'auth_providers.dart';
import 'history_repository.dart';
import 'offline_history_repository.dart';
import 'supabase_history_repository.dart';

/// Plays stored on this device under WM_OFFLINE, the user's own `sessions`
/// otherwise. Tests override this with a fake.
final historyRepositoryProvider = Provider<HistoryRepository>((ref) {
  if (Env.offline) {
    return OfflineHistoryRepository(
      ref.watch(sharedPrefsProvider),
      playerName: () => ref.read(authUserProvider)?.displayName,
    );
  }
  return SupabaseHistoryRepository(Supabase.instance.client);
});
