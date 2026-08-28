import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/avatar_spec.dart';

/// L'avatar-sigil : jamais une photo, un dégradé + une trame dérivés de [AvatarSpec] (voir
/// services/avatar.py côté backend — même principe, rendu ici côté client).
class AvatarSigil extends StatelessWidget {
  const AvatarSigil({super.key, required this.spec, this.size = 72});

  final AvatarSpec spec;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.35, -0.45),
                  colors: [spec.fromColor, spec.toColor],
                ),
                border: Border.all(color: spec.fromColor, width: 1.75),
              ),
            ),
            CustomPaint(
              painter: _StripePainter(angleDeg: spec.angleDeg),
              size: Size(size, size),
            ),
          ],
        ),
      ),
    );
  }
}

/// Trame diagonale légère : la "matière" qui distingue l'avatar-sigil d'un simple dégradé plat.
class _StripePainter extends CustomPainter {
  _StripePainter({required this.angleDeg});

  final double angleDeg;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.14)
      ..strokeWidth = 2;

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(angleDeg * math.pi / 180);
    canvas.translate(-size.width / 2, -size.height / 2);

    final diagonal = size.width + size.height;
    for (double x = -diagonal; x < diagonal; x += 9) {
      canvas.drawLine(Offset(x, -diagonal), Offset(x + diagonal, diagonal), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _StripePainter oldDelegate) => oldDelegate.angleDeg != angleDeg;
}
