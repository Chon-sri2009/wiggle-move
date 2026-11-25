import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'auth_repository.dart';

// Same key the pre-Supabase app used, so existing dev installs stay signed in.
const _nameKey = 'player_name';
const _emailKey = 'player_email';
const _offlineId = 'offline-user';

/// Local-only accounts for `--dart-define=WM_OFFLINE=true` and tests.
/// Sign-in and sign-up always succeed; only the display name and email are
/// kept on the device. The password is ignored.
class OfflineAuthRepository implements AuthRepository {
  OfflineAuthRepository(this._prefs);

  final SharedPreferences _prefs;
  final _changes = StreamController<AppUser?>.broadcast();

  @override
  AppUser? get currentUser {
    final name = _prefs.getString(_nameKey);
    if (name == null) return null;
    return AppUser(
      id: _offlineId,
      email: _prefs.getString(_emailKey) ?? '',
      displayName: name,
    );
  }

  @override
  Stream<AppUser?> get authChanges => _changes.stream;

  @override
  Future<void> signUp({
    required String email,
    required String password,
    required String displayName,
  }) => _store(email, displayName);

  @override
  Future<void> signIn({required String email, required String password}) =>
      _store(email, email.split('@').first);

  @override
  Future<void> signOut() async {
    await _prefs.remove(_nameKey);
    await _prefs.remove(_emailKey);
    _changes.add(null);
  }

  @override
  Future<void> sendPasswordReset(String email) async {}

  Future<void> _store(String email, String name) async {
    await _prefs.setString(_nameKey, name);
    await _prefs.setString(_emailKey, email);
    _changes.add(currentUser);
  }
}
