import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, PostgrestException;

import 'profile.dart';

/// Data error with a message that is safe to show the user.
class RepositoryFailure implements Exception {
  const RepositoryFailure(this.message);
  final String message;

  static const network =
      "Can't reach the server. Check your connection and try again.";
  static const sessionExpired =
      'Your session has expired. Please sign in again.';
  static const generic = 'Something went wrong. Please try again.';

  @override
  String toString() => 'RepositoryFailure($message)';
}

/// Maps any data-access error to a [RepositoryFailure]. Raw server text is
/// never used.
RepositoryFailure mapRepositoryException(Object error) {
  if (error is RepositoryFailure) return error;
  // On mobile, http's network ClientException also implements SocketException.
  if (error is SocketException || error is TimeoutException) {
    return const RepositoryFailure(RepositoryFailure.network);
  }
  if (error is AuthException) {
    return const RepositoryFailure(RepositoryFailure.sessionExpired);
  }
  if (error is PostgrestException) {
    // PGRST301: JWT expired/invalid.
    if (error.code == 'PGRST301' || error.code == '401') {
      return const RepositoryFailure(RepositoryFailure.sessionExpired);
    }
  }
  return const RepositoryFailure(RepositoryFailure.generic);
}

/// The signed-in user's profile. Implementations: `SupabaseProfileRepository`
/// (the user's own `profiles` row) and `OfflineProfileRepository`
/// (WM_OFFLINE, on-device).
///
/// Every method throws [RepositoryFailure] on error.
abstract class ProfileRepository {
  /// The current user's profile; a default, not-onboarded profile when none
  /// is stored yet.
  Future<Profile> load();

  Future<void> save(Profile profile);
}
