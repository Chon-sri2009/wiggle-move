import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/backend/auth_providers.dart';
import '../../shared/backend/profile_repository.dart';
import '../../shared/widgets/async_states.dart';
import 'profile_store.dart';
import '../../shared/l10n/app_language.dart';

/// Shown at `/loading` while the signed-in user's profile loads, or with a
/// Retry button if loading failed. The router moves on once it has loaded.
class ProfileLoadingScreen extends ConsumerWidget {
  const ProfileLoadingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final error = profile.error;
    return Scaffold(
      body: SafeArea(
        child: profile.isLoading || error == null
            ? const LoadingView()
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ErrorView(
                    message: error is RepositoryFailure
                        ? error.message
                        : RepositoryFailure.generic,
                    onRetry: () => ref.invalidate(profileProvider),
                  ),
                  // A way out when the profile never loads.
                  TextButton(
                    onPressed: () =>
                        ref.read(authRepositoryProvider).signOut().ignore(),
                    child: Text(context.tr('Sign out')),
                  ),
                ],
              ),
      ),
    );
  }
}
