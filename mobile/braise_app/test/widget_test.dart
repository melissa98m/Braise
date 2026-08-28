// Tests réels sur le système de design (docs/DESIGN_TOKENS.md), pas le test compteur par défaut
// de `flutter create` : celui-ci référençait MyApp, qui n'existe plus (voir lib/main.dart).
// Un test qui monterait BraiseApp ferait un vrai appel réseau (AuthController.restoreSession) —
// hors de portée sans mock HTTP pour cette passe.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:braise_app/theme/braise_theme.dart';
import 'package:braise_app/theme/braise_tokens.dart';

void main() {
  // Pas d'accès réseau en test : on désactive le fetch runtime des polices Google Fonts. Ça
  // laisse buildBraiseTheme() résoudre chaque police en tâche async (fallback silencieux, aucune
  // police bundlée en test) — d'où testWidgets + pumpAndSettle ci-dessous plutôt que test() nu,
  // pour que cette tâche soit attendue dans la zone du test au lieu de fuiter après coup.
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('le thème sombre respecte les tokens de fond', (tester) async {
    final theme = buildBraiseTheme(Brightness.dark);
    await tester.pumpWidget(MaterialApp(theme: theme, home: const SizedBox()));
    await tester.pumpAndSettle();
    expect(theme.scaffoldBackgroundColor, BraiseTokens.dark.surfaceRoot);
    expect(theme.brightness, Brightness.dark);
  });

  testWidgets('le thème clair respecte les tokens de fond', (tester) async {
    final theme = buildBraiseTheme(Brightness.light);
    await tester.pumpWidget(MaterialApp(theme: theme, home: const SizedBox()));
    await tester.pumpAndSettle();
    expect(theme.scaffoldBackgroundColor, BraiseTokens.light.surfaceRoot);
    expect(theme.brightness, Brightness.light);
  });

  test('le plancher de gris tient le contraste minimum documenté (4,5:1)', () {
    // docs/DESIGN_TOKENS.md : #7C879E (sombre) / #6F6759 (clair) sont les gris les plus
    // sombres/clairs autorisés, à 4,6:1 / 4,9:1 sur leur fond respectif — jamais plus bas.
    expect(_contrastRatio(BraiseTokens.dark.inkFloor, BraiseTokens.dark.surfaceRoot), greaterThanOrEqualTo(4.5));
    expect(_contrastRatio(BraiseTokens.light.inkFloor, BraiseTokens.light.surfaceRoot), greaterThanOrEqualTo(4.5));
  });
}

double _contrastRatio(Color a, Color b) {
  final lumA = a.computeLuminance();
  final lumB = b.computeLuminance();
  final lighter = lumA > lumB ? lumA : lumB;
  final darker = lumA > lumB ? lumB : lumA;
  return (lighter + 0.05) / (darker + 0.05);
}
