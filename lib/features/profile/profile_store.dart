import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/backend/auth_providers.dart';
import '../../shared/backend/profile.dart';
import '../../shared/backend/profile_providers.dart';

/// The signed-in user's profile. Reloads whenever the user id changes and is
/// a default (not onboarded) profile while signed out, so one account never
/// sees another's answers.
class ProfileNotifier extends AsyncNotifier<Profile> {
  @override
  FutureOr<Profile> build() {
    final uid = ref.watch(authUserProvider.select((u) => u?.id));
    if (uid == null) return const Profile();
    return ref.watch(profileRepositoryProvider).load();
  }

  /// Saves the answers, then marks the user onboarded. Throws
  /// `RepositoryFailure` and leaves the state unchanged if the save fails.
  Future<void> complete({
    required List<String> goals,
    required List<String> styles,
    required String level,
  }) async {
    await save(
      Profile(
        goals: goals,
        styles: styles,
        level: level,
        avatar: state.value?.avatar,
        onboarded: true,
      ),
    );
  }

  /// Persists [profile] and, once saved, makes it the current one. Throws
  /// `RepositoryFailure` and leaves the state unchanged if the save fails.
  Future<void> save(Profile profile) async {
    await ref.read(profileRepositoryProvider).save(profile);
    state = AsyncData(profile);
  }
}

final profileProvider = AsyncNotifierProvider<ProfileNotifier, Profile>(
  ProfileNotifier.new,
  // Failures are shown with a Retry button instead of retried silently.
  retry: (_, _) => null,
);
