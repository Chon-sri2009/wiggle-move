import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import '../../shared/backend/profile_repository.dart';
import '../../shared/widgets/async_states.dart';
import 'trainers_provider.dart';

/// User-safe message for a content load error.
String contentErrorMessage(Object? error) =>
    error is RepositoryFailure ? error.message : RepositoryFailure.generic;

/// Builds [builder] with the item [lookup] finds in the loaded content.
/// Whenever content is present it is used (a background refresh never
/// replaces a running screen with a spinner); otherwise shows loading, an
/// error with Retry, or [notFound] once content loaded without the item.
class ContentGate<T extends Object> extends ConsumerWidget {
  const ContentGate({
    super.key,
    required this.lookup,
    required this.builder,
    required this.notFound,
  });

  final ProviderListenable<T?> lookup;
  final Widget Function(T item) builder;
  final Widget notFound;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(lookup);
    if (item != null) return builder(item);
    final content = ref.watch(trainersProvider);
    if (content.hasValue) return notFound;
    return Scaffold(
      appBar: AppBar(),
      body: content.hasError
          ? ErrorView(
              message: contentErrorMessage(content.error),
              onRetry: () => ref.read(trainersProvider.notifier).refresh(),
            )
          : const LoadingView(),
    );
  }
}
