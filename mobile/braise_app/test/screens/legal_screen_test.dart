// LegalScreen (CGU + privacy policy) is pure static content, no network/state — reached from
// WelcomeScreen (before signup) and SettingsScreen (after). Tests just check both tabs render
// their expected content and that switching tabs works.

import 'package:braise_app/screens/legal/legal_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

Widget _harness() {
  return const MaterialApp(home: LegalScreen());
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('shows both tabs and the CGU content by default', (tester) async {
    await tester.pumpWidget(_harness());

    expect(find.text('CGU'), findsOneWidget);
    expect(find.text('Confidentialité'), findsOneWidget);
    expect(find.text('Statut bêta'), findsOneWidget);
  });

  testWidgets('switching to the privacy tab shows its content', (tester) async {
    await tester.pumpWidget(_harness());

    await tester.tap(find.text('Confidentialité'));
    await tester.pumpAndSettle();

    expect(find.text('Quelles données, pourquoi'), findsOneWidget);
  });
}
