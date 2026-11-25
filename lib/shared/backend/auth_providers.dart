import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/leaderboard/leaderboard_store.dart'
    show sharedPrefsProvider;
import '../env.dart';
import 'auth_repository.dart';
import 'offline_auth_repository.dart';
import 'supabase_auth_repository.dart';

/// Offline (local) accounts under WM_OFFLINE, Supabase otherwise.
/// Tests override this with a fake.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  if (Env.offline) {
    return OfflineAuthRepository(ref.watch(sharedPrefsProvider));
  }
  return SupabaseAuthRepository(Supabase.instance.client.auth);
});

/// The signed-in user (null when signed out). Seeded synchronously from the
/// repository so a restored session skips the login screen.
class AuthUserNotifier extends Notifier<AppUser?> {
  @override
  AppUser? build() {
    final repo = ref.watch(authRepositoryProvider);
    // Supabase reports e.g. a failed token refresh as a stream error; keep
    // the current state rather than crashing with an uncaught error.
    final sub = repo.authChanges.listen(
      (user) => state = user,
      onError: (Object _) {},
    );
    ref.onDispose(sub.cancel);
    return repo.currentUser;
  }
}

final authUserProvider = NotifierProvider<AuthUserNotifier, AppUser?>(
  AuthUserNotifier.new,
);
