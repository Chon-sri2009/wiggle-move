import 'package:flutter/material.dart';

import '../l10n/app_language.dart';

void showAppSnackBar(
  BuildContext context,
  String message, {
  bool isError = false,
}) {
  final scheme = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        context.tr(message),
        style: isError ? TextStyle(color: scheme.onError) : null,
      ),
      backgroundColor: isError ? scheme.error : null,
    ),
  );
}
