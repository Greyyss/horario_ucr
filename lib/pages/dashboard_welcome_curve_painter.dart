import 'package:flutter/material.dart';

class WelcomeCurvePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final outerPath = Path()
      ..moveTo(0, 0)
      ..lineTo(w * 0.52, 0)
      ..cubicTo(
        w * 0.64,
        h * 0.25,
        w * 0.64,
        h * 0.75,
        w * 0.58,
        h,
      )
      ..lineTo(0, h)
      ..close();

    canvas.drawPath(
      outerPath,
      Paint()
        ..color = const Color(0xFF4BA9ED).withValues(
          alpha: 0.70,
        ),
    );

    final middlePath = Path()
      ..moveTo(0, 0)
      ..lineTo(w * 0.48, 0)
      ..cubicTo(
        w * 0.60,
        h * 0.25,
        w * 0.60,
        h * 0.75,
        w * 0.54,
        h,
      )
      ..lineTo(0, h)
      ..close();

    canvas.drawPath(
      middlePath,
      Paint()
        ..color = const Color(0xFFB7E3FF).withValues(
          alpha: 0.96,
        ),
    );

    final innerPath = Path()
      ..moveTo(0, 0)
      ..lineTo(w * 0.43, 0)
      ..cubicTo(
        w * 0.55,
        h * 0.25,
        w * 0.55,
        h * 0.75,
        w * 0.49,
        h,
      )
      ..lineTo(0, h)
      ..close();

    canvas.drawPath(
      innerPath,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color(0xFFF5FAFF),
            Color(0xFFE8F6FF),
            Color(0xFFD4EDFF),
          ],
        ).createShader(
          Offset.zero & size,
        ),
    );
  }

  @override
  bool shouldRepaint(
    covariant CustomPainter oldDelegate,
  ) {
    return false;
  }
}
