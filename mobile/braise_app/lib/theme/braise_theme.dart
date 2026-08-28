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
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: tokens.inkPrimary,
        minimumSize: const Size.fromHeight(52),
        side: BorderSide(color: tokens.borderHairline),
        textStyle: GoogleFonts.manrope(fontWeight: FontWeight.w600, fontSize: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(BraiseRadii.card)),
      ),
    ),
    // Anneau de focus violet 3px, jamais supprimé (docs/DESIGN_TOKENS.md, accessibilité).
    focusColor: tokens.focusRing,
  );
}
