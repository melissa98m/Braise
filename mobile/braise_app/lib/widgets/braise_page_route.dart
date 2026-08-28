import 'package:flutter/material.dart';

/// Transition d'écran commune : fondu + léger glissement vers le haut, jamais un simple cut.
/// Respecte `prefers-reduced-motion` (docs/DESIGN_TOKENS.md, accessibilité) via
/// `MediaQuery.disableAnimations` — durée nulle plutôt que le mouvement désactivé au hasard.
Route<T> braiseRoute<T>(BuildContext context, Widget page) {
  final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  final duration = reduceMotion ? Duration.zero : const Duration(milliseconds: 260);
  return PageRouteBuilder<T>(
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.03),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}
