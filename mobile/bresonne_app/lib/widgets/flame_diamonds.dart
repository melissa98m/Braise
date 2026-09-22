import 'package:flutter/material.dart';

import '../theme/braise_tokens.dart';

/// Diamants pleins/vides — jamais une couleur seule pour indiquer la progression
/// (docs/DESIGN_TOKENS.md, accessibilité). `filled` sur `total` diamants.
///
/// Un diamant qui vient de se remplir (ex. bonne réponse à la question du jour) fait un léger
/// pop d'échelle plutôt qu'un cut instantané — `prefers-reduced-motion` (`disableAnimations`)
/// le désactive et retombe sur le changement de couleur seul, comme avant.
class FlameDiamonds extends StatefulWidget {
  const FlameDiamonds({super.key, required this.filled, required this.total, this.size = 14});

  final int filled;
  final int total;
  final double size;

  @override
  State<FlameDiamonds> createState() => _FlameDiamondsState();
}

class _FlameDiamondsState extends State<FlameDiamonds> {
  late int _previousFilled = widget.filled;

  @override
  void didUpdateWidget(covariant FlameDiamonds oldWidget) {
    super.didUpdateWidget(oldWidget);
    _previousFilled = oldWidget.filled;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = BraiseTokens.of(context);
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final colorDuration = reduceMotion ? Duration.zero : const Duration(milliseconds: 260);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(widget.total, (i) {
        final isFilled = i < widget.filled;
        final justFilled = !reduceMotion && isFilled && i >= _previousFilled;
        return Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Transform.rotate(
            angle: 0.785398, // 45°
            child: TweenAnimationBuilder<double>(
              key: ValueKey(isFilled),
              tween: Tween(begin: justFilled ? 0.55 : 1, end: 1),
              duration: justFilled ? const Duration(milliseconds: 360) : Duration.zero,
              curve: Curves.easeOutQuint,
              builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
              child: AnimatedContainer(
                duration: colorDuration,
                curve: Curves.easeOutCubic,
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  color: isFilled ? tokens.braiseInk : Colors.transparent,
                  border: isFilled ? null : Border.all(color: tokens.borderStrong, width: 1.75),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
