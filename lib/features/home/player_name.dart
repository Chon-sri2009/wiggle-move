import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../leaderboard/leaderboard_store.dart';

/// Returns the player's name, asking for it first if not set. Null if cancelled.
Future<String?> ensurePlayerName(BuildContext context, WidgetRef ref) async {
  final existing = ref.read(playerNameProvider);
  if (existing != null) return existing;

  final controller = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('What should we call you?'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 20,
        decoration: const InputDecoration(
          hintText: 'Your name on the leaderboard',
        ),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (name == null || name.isEmpty) return null;
  await ref.read(playerNameProvider.notifier).set(name);
  return name;
}
