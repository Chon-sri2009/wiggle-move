import 'package:supabase_flutter/supabase_flutter.dart';

import 'profile.dart';
import 'profile_repository.dart';

/// The signed-in user's own `profiles` row (RLS allows only that row). The
/// row is created by the `handle_new_user` trigger at sign-up.
class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository(this._client);

  final SupabaseClient _client;

  static const _columns = 'goals, styles, level, onboarded';

  String get _uid {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw const RepositoryFailure(RepositoryFailure.sessionExpired);
    }
    return id;
  }

  @override
  Future<Profile> load() => _guard(() async {
    final row = await _client
        .from('profiles')
        .select(_columns)
        .eq('id', _uid)
        .maybeSingle();
    // Missing row (trigger not run yet): treat as a fresh, not-onboarded user.
    return row == null ? const Profile() : Profile.fromRow(row);
  });

  @override
  Future<void> save(Profile profile) => _guard(() async {
    final rows = await _client
        .from('profiles')
        .update(profile.toRow())
        .eq('id', _uid)
        .select('id');
    // An update that matches no row succeeds silently; don't report success.
    if (rows.isEmpty) {
      throw const RepositoryFailure(RepositoryFailure.generic);
    }
  });

  static Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } catch (e) {
      throw mapRepositoryException(e);
    }
  }
}
