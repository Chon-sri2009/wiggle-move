import 'package:flutter/material.dart';

/// Shown instead of the app when the `--dart-define` configuration is
/// unusable: required values are missing, or (with [message]) some other
/// configuration error.
class EnvErrorScreen extends StatelessWidget {
  const EnvErrorScreen({
    super.key,
    this.missing = const [],
    this.title = 'Missing configuration',
    this.message,
  });

  final List<String> missing;
  final String title;

  /// Replaces the missing-flags instructions when set.
  final String? message;

  @override
  Widget build(BuildContext context) {
    final flags = missing.map((m) => '--dart-define=$m=<value>').join('\n');
    final message = this.message;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                if (message != null)
                  Text(message)
                else ...[
                  const Text('Run the app with the following flags:'),
                  const SizedBox(height: 8),
                  SelectableText(
                    flags,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'For local development without Supabase, use '
                    '--dart-define=WM_OFFLINE=true.',
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
