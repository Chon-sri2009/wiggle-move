import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../env.dart';
import '../prefs.dart';
import 'content_cache.dart';
import 'content_repository.dart';
import 'offline_content_repository.dart';
import 'supabase_content_repository.dart';

/// Built-in content under WM_OFFLINE, the content tables otherwise.
/// Tests override this with a fake.
final contentRepositoryProvider = Provider<ContentRepository>((ref) {
  if (Env.offline) return const OfflineContentRepository();
  return SupabaseContentRepository(Supabase.instance.client);
});

final contentCacheProvider = Provider<ContentCache>(
  (ref) => ContentCache(ref.watch(sharedPrefsProvider)),
);
