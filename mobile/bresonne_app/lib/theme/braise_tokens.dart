import 'package:flutter/material.dart';

/// Valeurs issues de docs/DESIGN_TOKENS.md — une seule source de vérité pour les deux thèmes.
/// Ne jamais coder une couleur en dur ailleurs dans l'app : passer par [BraiseTokens.of(context)].
class BraiseTokens {
  const BraiseTokens({
    required this.surfaceRoot,
    required this.surface1,
    required this.surface2,
    required this.borderHairline,
    required this.borderStrong,
    required this.inkPrimary,
    required this.inkSecondary,
    required this.inkFloor,
    required this.braiseInk,
    required this.braiseFill,
    required this.braiseFillText,
    required this.braiseTint,
    required this.voileInk,
    required this.foiInk,
    required this.foiFill,
    required this.foiFillText,
    required this.alerte,
    required this.erreur,
    required this.focusRing,
  });

  final Color surfaceRoot;
  final Color surface1;
  final Color surface2;
  final Color borderHairline;
  final Color borderStrong;
  final Color inkPrimary;
  final Color inkSecondary;
  final Color inkFloor;
  final Color braiseInk;
  final Color braiseFill;
  final Color braiseFillText;
  final Color braiseTint;
  final Color voileInk;
  final Color foiInk;
  final Color foiFill;
  final Color foiFillText;
  final Color alerte;
  final Color erreur;
  final Color focusRing;

  static const dark = BraiseTokens(
    surfaceRoot: Color(0xFF07090E),
    surface1: Color(0xFF0F1420),
    surface2: Color(0xFF1D2434),
    borderHairline: Color(0xFF2C3448),
    borderStrong: Color(0xFF3A4459),
    inkPrimary: Color(0xFFF4F1EA),
    inkSecondary: Color(0xFFAAB3C8),
    inkFloor: Color(0xFF7C879E),
    braiseInk: Color(0xFFFF8C42),
    braiseFill: Color(0xFFFF8C42),
    braiseFillText: Color(0xFF160B03),
    braiseTint: Color(0x24FF8C42), // rgba(255,140,66,.14)
    voileInk: Color(0xFF9E8CFF),
    foiInk: Color(0xFF57D9B0),
    foiFill: Color(0xFF57D9B0),
    foiFillText: Color(0xFF04231A),
    alerte: Color(0xFFFFC761),
    erreur: Color(0xFFFF7B7B),
    focusRing: Color(0xFF9E8CFF),
  );

  static const light = BraiseTokens(
    surfaceRoot: Color(0xFFFBF8F3),
    surface1: Color(0xFFFFFFFF),
    surface2: Color(0xFFF1ECE3),
    borderHairline: Color(0xFFDDD5C7),
    borderStrong: Color(0xFFC6BCAA),
    inkPrimary: Color(0xFF1A1712),
    inkSecondary: Color(0xFF6B6255),
    inkFloor: Color(0xFF6F6759),
    braiseInk: Color(0xFFA8460A),
    braiseFill: Color(0xFFA8460A),
    braiseFillText: Color(0xFFFFF6EE),
    braiseTint: Color(0x1AA8460A), // rgba(168,70,10,.10)
    voileInk: Color(0xFF5B45D6),
    foiInk: Color(0xFF0F7A5E),
    foiFill: Color(0xFF0F7A5E),
    foiFillText: Color(0xFFEAFFF8),
    alerte: Color(0xFF8A6300),
    erreur: Color(0xFFC0392B),
    focusRing: Color(0xFF5B45D6),
  );

  static BraiseTokens of(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }
}

/// Rythme d'espacement base 4 / rythme 8 (docs/DESIGN_TOKENS.md).
class BraiseSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 28.0;
}

/// Rayons par niveau de surface (docs/DESIGN_TOKENS.md).
class BraiseRadii {
  static const field = 12.0;
  static const card = 16.0;
  static const keyCard = 22.0;
  static const media = 26.0;
}
