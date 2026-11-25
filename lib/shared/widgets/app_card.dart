import 'package:flutter/material.dart';

/// Themed card, optionally with inner [padding].
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.clipBehavior,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Clip? clipBehavior;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: clipBehavior,
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );
  }
}
