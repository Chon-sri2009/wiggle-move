import 'package:flutter/material.dart';

/// Shown instead of the app when required `--dart-define` values are missing.
class EnvErrorScreen extends StatelessWidget {
  const EnvErrorScreen({super.key, required this.missing});

  final List<String> missing;

  @override
  Widget build(BuildContext context) {
    final flags = missing.map((m) => '--dart-define=$m=<value>').join('\n');
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
                const Text(
                  'Missing configuration',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
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
            ),
          ),
        ),
      ),
    );
  }
}
