import 'package:flutter/material.dart';

import '../theme/braise_tokens.dart';

/// Diamants pleins/vides — jamais une couleur seule pour indiquer la progression
/// (docs/DESIGN_TOKENS.md, accessibilité). `filled` sur `total` diamants.
class FlameDiamonds extends StatelessWidget {
  const FlameDiamonds({super.key, required this.filled, required this.total, this.size = 14});

  final int filled;
  final int total;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = BraiseTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(total, (i) {
        final isFilled = i < filled;
        return Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Transform.rotate(
            angle: 0.785398, // 45°
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: isFilled ? tokens.braiseInk : Colors.transparent,
                border: isFilled ? null : Border.all(color: tokens.borderStrong, width: 1.75),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        );
      }),
    );
  }
}
