import 'package:flutter/material.dart';

/// L'alphabet de 4 primitives de docs/DESIGN_TOKENS.md (diamant, cercle, carré, barre) — chaque
/// signe a une forme distincte, jamais seulement une couleur. Réutilisé par la barre d'onglets et
/// les badges de statut plutôt que des icônes Material génériques.
class SignCircleOutline extends StatelessWidget {
  const SignCircleOutline({super.key, required this.color, this.size = 18, this.strokeWidth = 2});

  final Color color;
  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: strokeWidth),
      ),
    );
  }
}

class SignFilledCircle extends StatelessWidget {
  const SignFilledCircle({super.key, required this.color, this.size = 18});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

class SignSquareOutline extends StatelessWidget {
  const SignSquareOutline({super.key, required this.color, this.size = 18, this.strokeWidth = 2});

  final Color color;
  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        border: Border.all(color: color, width: strokeWidth),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
    );
  }
}

/// Le voile : cercle hachuré — profil privé encore tenu.
class SignHatchedCircle extends StatelessWidget {
  const SignHatchedCircle({super.key, required this.color, this.size = 22, this.trackColor});

  final Color color;
  final Color? trackColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: trackColor,
        border: Border.all(color: color, width: 1.75),
      ),
      child: ClipOval(
        child: CustomPaint(painter: _HatchPainter(color: color), size: Size(size, size)),
      ),
    );
  }
}

class _HatchPainter extends CustomPainter {
  _HatchPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(0.65);
    canvas.translate(-size.width / 2, -size.height / 2);
    final diagonal = size.width + size.height;
    for (double x = -diagonal; x < diagonal; x += 6) {
      canvas.drawLine(Offset(x, -diagonal), Offset(x, diagonal), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HatchPainter oldDelegate) => oldDelegate.color != color;
}

/// Carré à noyau : identité contrôlée.
class SignSquareCore extends StatelessWidget {
  const SignSquareCore({super.key, required this.color, this.size = 26});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1.75),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Transform.rotate(
        angle: 0.785398,
        child: Container(
          width: size * 0.38,
          height: size * 0.38,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
        ),
      ),
    );
  }
}

/// Diamant unique (plein ou contour) — même primitive que [FlameDiamonds] mais isolée.
class SignDiamond extends StatelessWidget {
  const SignDiamond({super.key, required this.color, this.size = 16, this.filled = true});

  final Color color;
  final double size;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: 0.785398,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: filled ? color : Colors.transparent,
          border: filled ? null : Border.all(color: color, width: 1.75),
          borderRadius: BorderRadius.circular(size * 0.28),
        ),
      ),
    );
  }
}
