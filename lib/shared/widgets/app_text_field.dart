import 'package:flutter/material.dart';

import '../l10n/app_language.dart';

/// Themed form field (fill, pill border and padding come from the theme).
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    required this.hint,
    this.validator,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.obscureText = false,
  });

  final TextEditingController controller;
  final String hint;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      obscureText: obscureText,
      decoration: InputDecoration(labelText: context.tr(hint)),
      // Validators return English; translate the message for display.
      validator: validator == null
          ? null
          : (v) {
              final message = validator!(v);
              return message == null ? null : context.tr(message);
            },
    );
  }
}
