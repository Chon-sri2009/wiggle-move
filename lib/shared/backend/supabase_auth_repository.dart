import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_repository.dart';

/// Email/password accounts on Supabase Auth. The session is persisted and
/// restored by supabase_flutter itself.
class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(
    this._auth,
    this._functions, {
    this.timeout = const Duration(seconds: 20),
  });

  static const deleteFunctionName = 'delete_account';

  final GoTrueClient _auth;
  final FunctionsClient _functions;
  final Duration timeout;

  @override
  AppUser? get currentUser => toAppUser(_auth.currentUser);

  @override
  Stream<AppUser?> get authChanges =>
      _auth.onAuthStateChange.map((s) => toAppUser(s.session?.user));

  @override
  Future<void> signUp({
    required String email,
    required String password,
    required String displayName,
  }) => _guard(
    // The handle_new_user trigger reads raw_user_meta_data.display_name.
    () => _auth.signUp(
      email: email,
      password: password,
      data: {'display_name': displayName},
    ),
  );

  @override
  Future<void> signIn({required String email, required String password}) =>
      _guard(() => _auth.signInWithPassword(email: email, password: password));

  @override
  Future<void> signOut() => _guard(_auth.signOut);

  @override
  Future<void> sendPasswordReset(String email) =>
      _guard(() => _auth.resetPasswordForEmail(email));

  @override
  Future<void> updateDisplayName(String name) => _guard(
    () => _auth.updateUser(UserAttributes(data: {'display_name': name})),
  );

  /// The `delete_account` Edge Function removes the auth user (the profile,
  /// sessions and results cascade). The local session is then dropped; the
  /// server no longer knows it, so only this device is signed out.
  @override
  Future<void> deleteAccount() => _guard(() async {
    final res = await _functions.invoke(deleteFunctionName).timeout(timeout);
    if (res.status < 200 || res.status >= 300) {
      throw const AuthFailure(AuthFailure.generic);
    }
    await _auth.signOut(scope: SignOutScope.local);
  });

  static Future<void> _guard(Future<void> Function() call) async {
    try {
      await call();
    } catch (e) {
      throw mapAuthException(e);
    }
  }

  static AppUser? toAppUser(User? user) {
    if (user == null) return null;
    final email = user.email ?? '';
    final name = user.userMetadata?['display_name'];
    return AppUser(
      id: user.id,
      email: email,
      displayName: name is String && name.trim().isNotEmpty
          ? name
          : email.split('@').first,
    );
  }
}
