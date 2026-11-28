import 'package:flutter/material.dart';

import 'theme.dart';

/// The WiggleMove logo from the Figma: an orange leaping rabbit above the
/// navy wordmark.
///
/// The rabbit is drawn as a vector ([RabbitPainter]) so it stays sharp at any
/// size. It was traced by eye from the Figma overview, so swap it for the
/// exported SVG/PNG if exact curves matter (the wordmark is plain text too).
class WiggleLogo extends StatelessWidget {
  const WiggleLogo({super.key, this.size = 28});

  /// Font size of the wordmark; the rabbit is as wide as the wordmark.
  final double size;

  @override
  Widget build(BuildContext context) {
    final rabbitWidth = size * 4.2;
    return Semantics(
      label: 'WiggleMove',
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: rabbitWidth,
              height: rabbitWidth * RabbitPainter.aspect,
              child: const CustomPaint(painter: RabbitPainter()),
            ),
            const SizedBox(height: 4),
            // Scales down instead of wrapping when the system text is large.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'WiggleMove',
                maxLines: 1,
                style: TextStyle(
                  fontSize: size,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The leaping rabbit: ear swept back, body arched, facing right.
class RabbitPainter extends CustomPainter {
  const RabbitPainter();

  /// height / width of the drawing.
  static const aspect = 0.6;

  // Drawn in a 400 x 240 box, then scaled to the available size.
  static const _w = 400.0, _h = 240.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / _w, size.height / _h);
    final body = Path()
      ..moveTo(10, 225) // back foot
      ..cubicTo(50, 165, 130, 120, 235, 100) // back
      ..cubicTo(200, 88, 145, 50, 125, 17) // ear, lower edge
      ..cubicTo(160, 5, 220, 13, 270, 55) // ear, top edge
      ..cubicTo(300, 80, 340, 80, 365, 93) // head
      ..cubicTo(395, 110, 400, 145, 380, 165) // face
      ..cubicTo(365, 175, 345, 175, 325, 170) // chin
      ..cubicTo(340, 190, 365, 215, 380, 233) // front paw
      ..cubicTo(340, 220, 310, 200, 280, 195) // under the chest
      ..cubicTo(200, 193, 100, 210, 10, 225) // belly
      ..close();
    canvas.drawPath(body, Paint()..color = AppColors.accent);
    // Eye.
    canvas.drawCircle(
      const Offset(352, 123),
      4,
      Paint()..color = const Color(0xFFFFE0CC),
    );
  }

  @override
  bool shouldRepaint(RabbitPainter old) => false;
}
