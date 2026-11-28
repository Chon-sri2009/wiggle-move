import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../env.dart';
import '../prefs.dart';
import 'offline_profile_repository.dart';
import 'profile_repository.dart';
import 'supabase_profile_repository.dart';

/// On-device profile under WM_OFFLINE, the `profiles` table otherwise.
/// Tests override this with a fake.
final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  if (Env.offline) {
    return OfflineProfileRepository(ref.watch(sharedPrefsProvider));
  }
  return SupabaseProfileRepository(Supabase.instance.client);
});
