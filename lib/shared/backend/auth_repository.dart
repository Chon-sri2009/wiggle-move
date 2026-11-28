import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, AuthRetryableFetchException, FunctionsFetchException;

/// The signed-in user as the app sees it.
class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.displayName,
  });

  final String id;
  final String email;
  final String displayName;

  @override
  bool operator ==(Object other) =>
      other is AppUser &&
      other.id == id &&
      other.email == email &&
      other.displayName == displayName;

  @override
  int get hashCode => Object.hash(id, email, displayName);
}

/// Auth error with a message that is safe to show the user.
class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;

  static const invalidCredentials = 'Email or password is incorrect.';
  static const userExists = 'An account with this email already exists.';
  static const weakPassword =
      'That password is too weak. Use at least 8 characters with letters and numbers.';
  static const emailNotConfirmed =
      'Please confirm your email first. Check your inbox for the link.';
  static const network =
      "Can't reach the server. Check your connection and try again.";
  static const rateLimited =
      'Too many attempts. Please wait a moment and try again.';
  static const generic = 'Something went wrong. Please try again.';

  @override
  String toString() => 'AuthFailure($message)';
}

/// Maps any auth error to an [AuthFailure]. Raw server text is never used.
AuthFailure mapAuthException(Object error) {
  if (error is AuthFailure) return error;
  if (error is SocketException ||
      error is TimeoutException ||
      error is FunctionsFetchException) {
    return const AuthFailure(AuthFailure.network);
  }
  if (error is! AuthException) return const AuthFailure(AuthFailure.generic);
  // Network failures are wrapped by gotrue as AuthRetryableFetchException
  // (no status code, no error code).
  if (error is AuthRetryableFetchException) {
    return const AuthFailure(AuthFailure.network);
  }
  switch (error.code) {
    case 'invalid_credentials':
      return const AuthFailure(AuthFailure.invalidCredentials);
    case 'user_already_exists':
    case 'email_exists':
      return const AuthFailure(AuthFailure.userExists);
    case 'weak_password':
      return const AuthFailure(AuthFailure.weakPassword);
    case 'email_not_confirmed':
      return const AuthFailure(AuthFailure.emailNotConfirmed);
    case 'over_request_rate_limit':
    case 'over_email_send_rate_limit':
      return const AuthFailure(AuthFailure.rateLimited);
  }
  if (error.statusCode == '429') {
    return const AuthFailure(AuthFailure.rateLimited);
  }
  return const AuthFailure(AuthFailure.generic);
}

/// Account access. Implementations: `SupabaseAuthRepository` (real backend)
/// and `OfflineAuthRepository` (WM_OFFLINE dev mode and tests).
///
/// Every method throws [AuthFailure] on error.
abstract class AuthRepository {
  AppUser? get currentUser;

  /// Emits the user whenever the session changes (null when signed out).
  Stream<AppUser?> get authChanges;

  Future<void> signUp({
    required String email,
    required String password,
    required String displayName,
  });

  Future<void> signIn({required String email, required String password});

  Future<void> signOut();

  Future<void> sendPasswordReset(String email);

  /// Emits when the user opened a password-reset link: the app is then signed
  /// in with a recovery session and must ask for a new password.
  Stream<void> get passwordRecovery;

  /// Sets a new password for the signed-in user.
  Future<void> updatePassword(String password);

  /// Changes the name the app shows for the signed-in user.
  Future<void> updateDisplayName(String name);

  /// Permanently deletes the signed-in account and its data, then signs out.
  Future<void> deleteAccount();
}
