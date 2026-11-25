import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/backend/profile_repository.dart';
import '../../shared/widgets/async_states.dart';
import 'profile_store.dart';

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
            : ErrorView(
                message: error is RepositoryFailure
                    ? error.message
                    : RepositoryFailure.generic,
                onRetry: () => ref.invalidate(profileProvider),
              ),
      ),
    );
  }
}
