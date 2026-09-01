import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'braise_tokens.dart';

/// Construit le ThemeData Braise pour un [Brightness] donné, à partir des tokens
/// docs/DESIGN_TOKENS.md. Bricolage Grotesque (display/titres), Manrope (corps, 17px min.),
/// IBM Plex Mono (données/labels, +14% d'interlettrage) — jamais d'autre police.
ThemeData buildBraiseTheme(Brightness brightness) {
  final tokens = brightness == Brightness.dark ? BraiseTokens.dark : BraiseTokens.light;

  final textTheme = TextTheme(
    // Display — Bricolage Grotesque 800 · 34/38 · -3%
    displayLarge: GoogleFonts.bricolageGrotesque(
      fontWeight: FontWeight.w800,
      fontSize: 34,
      height: 38 / 34,
      letterSpacing: -34 * 0.03,
      color: tokens.inkPrimary,
    ),
    // Titre écran — Bricolage 700 · 26/32
    headlineMedium: GoogleFonts.bricolageGrotesque(
      fontWeight: FontWeight.w700,
      fontSize: 26,
      height: 32 / 26,
      letterSpacing: -26 * 0.02,
      color: tokens.inkPrimary,
    ),
    // Corps — Manrope 500 · 17/27 (min. 17px)
    bodyLarge: GoogleFonts.manrope(
      fontWeight: FontWeight.w500,
      fontSize: 17,
      height: 27 / 17,
      color: tokens.inkPrimary,
    ),
    // Secondaire — Manrope 500 · 15/22
    bodyMedium: GoogleFonts.manrope(
      fontWeight: FontWeight.w500,
      fontSize: 15,
      height: 22 / 15,
      color: tokens.inkSecondary,
    ),
    // Données / labels — IBM Plex Mono 500 · 13 · +14%
    labelSmall: GoogleFonts.ibmPlexMono(
      fontWeight: FontWeight.w500,
      fontSize: 13,
      letterSpacing: 13 * 0.14,
      color: tokens.inkSecondary,
    ),
    titleLarge: GoogleFonts.bricolageGrotesque(
      fontWeight: FontWeight.w700,
      fontSize: 22,
      letterSpacing: -22 * 0.015,
      color: tokens.inkPrimary,
    ),
    titleMedium: GoogleFonts.bricolageGrotesque(
      fontWeight: FontWeight.w700,
      fontSize: 19,
      color: tokens.inkPrimary,
    ),
    bodySmall: GoogleFonts.manrope(
      fontWeight: FontWeight.w600,
      fontSize: 16,
      color: tokens.inkPrimary,
    ),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: tokens.surfaceRoot,
    canvasColor: tokens.surfaceRoot,
    primaryColor: tokens.braiseInk,
    dividerColor: tokens.borderHairline,
    textTheme: textTheme,
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: tokens.braiseInk,
      onPrimary: tokens.braiseFillText,
      secondary: tokens.voileInk,
      onSecondary: tokens.inkPrimary,
      error: tokens.erreur,
      onError: tokens.inkPrimary,
      surface: tokens.surface1,
      onSurface: tokens.inkPrimary,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: tokens.surfaceRoot,
      foregroundColor: tokens.inkPrimary,
      elevation: 0,
      titleTextStyle: textTheme.titleLarge,
    ),
    cardTheme: CardThemeData(
      color: tokens.surface1,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BraiseRadii.card),
        side: BorderSide(color: tokens.borderHairline),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: tokens.surface2,
      contentPadding: const EdgeInsets.all(BraiseSpacing.lg),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(BraiseRadii.field),
        borderSide: BorderSide(color: tokens.borderStrong),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(BraiseRadii.field),
        borderSide: BorderSide(color: tokens.borderStrong),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(BraiseRadii.field),
        borderSide: BorderSide(color: tokens.focusRing, width: 3),
      ),
      hintStyle: textTheme.bodyLarge?.copyWith(color: tokens.inkFloor),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: tokens.braiseFill,
        foregroundColor: tokens.braiseFillText,
        minimumSize: const Size.fromHeight(56),
        textStyle: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 17),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(BraiseRadii.card)),
        // Halo ambré sous le CTA primaire — motif répété dans toute la maquette
        // (box-shadow 0 10px 30px rgba(braise,.28)), jamais un simple bouton plat.
        elevation: 8,
        shadowColor: tokens.braiseFill.withValues(alpha: 0.55),
      ).copyWith(side: _focusRingSide(tokens)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: tokens.inkPrimary,
        minimumSize: const Size.fromHeight(52),
        side: BorderSide(color: tokens.borderHairline),
        textStyle: GoogleFonts.manrope(fontWeight: FontWeight.w600, fontSize: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(BraiseRadii.card)),
      ).copyWith(side: _focusRingSide(tokens, fallback: BorderSide(color: tokens.borderHairline))),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: tokens.braiseInk,
      ).copyWith(side: _focusRingSide(tokens)),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom().copyWith(side: _focusRingSide(tokens)),
    ),
    // `focusColor` reste le survol de teinte par défaut de Flutter (utilisé par ex. sur InkWell) ;
    // insuffisant seul pour les boutons (~24/255 de variation de couleur, imperceptible sur un
    // fond saturé) — d'où l'anneau visible ci-dessus sur chaque type de bouton, jamais retiré
    // (docs/DESIGN_TOKENS.md, accessibilité). Trouvé en mesurant un vrai écran focus/non-focus au
    // pixel près, pas en relisant le thème.
    focusColor: tokens.focusRing,
  );
}

/// Anneau de focus clavier visible (3px, `tokens.focusRing`) sur un type de bouton donné — sans
/// ça, Material ne fait qu'un survol de teinte quasi invisible (`ThemeData.focusColor`) au focus.
/// `fallback` est la bordure du reste des états (ex. la bordure fine d'un `OutlinedButton`) ;
/// `null` par défaut pour un bouton normalement sans bordure (Elevated/Text/Icon).
WidgetStateProperty<BorderSide?> _focusRingSide(BraiseTokens tokens, {BorderSide? fallback}) {
  return WidgetStateProperty.resolveWith((states) {
    if (states.contains(WidgetState.focused)) {
      return BorderSide(color: tokens.focusRing, width: 3);
    }
    return fallback;
  });
}
