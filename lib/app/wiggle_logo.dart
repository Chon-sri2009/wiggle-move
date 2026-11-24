import 'package:flutter/material.dart';

import 'theme.dart';

/// Stand-in for the Figma rabbit logo until the real asset is exported
/// (add it under assets/ and swap this widget's body for an Image).
class WiggleLogo extends StatelessWidget {
  const WiggleLogo({super.key, this.size = 28});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'WiggleMove',
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.directions_run,
              size: size * 1.6,
              color: AppColors.accent,
            ),
            Text(
              'WiggleMove',
              style: TextStyle(
                fontSize: size,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
