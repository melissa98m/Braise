// LegalScreen (CGU + privacy policy + mentions légales + community rules, 4 tabs) is pure static
// content, no network/state — reached from WelcomeScreen (before signup) and SettingsScreen
// (after). Tests just check each tab renders its expected content and that switching tabs works.

import 'package:bresonne_app/screens/legal/legal_screen.dart';
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

  testWidgets('initialTab opens directly on the privacy tab', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LegalScreen(initialTab: 1)));
    await tester.pumpAndSettle();

    expect(find.text('Quelles données, pourquoi'), findsOneWidget);
  });

  testWidgets('switching to the mentions légales tab shows its content', (tester) async {
    await tester.pumpWidget(_harness());

    await tester.tap(find.text('Mentions légales'));
    await tester.pumpAndSettle();

    expect(find.text('Éditeurs'), findsOneWidget);
  });

  testWidgets('initialTab opens directly on the community rules tab', (tester) async {
    // 4 sections of body text overflow the default 600px test viewport, and the underlying
    // Sliver never builds elements past its cacheExtent — same trap as SettingsScreen's long
    // list (see its comment). A taller surface, not a scroll, is the established fix here.
    final originalSize = tester.view.physicalSize;
    final originalRatio = tester.view.devicePixelRatio;
    addTearDown(() {
      tester.view.physicalSize = originalSize;
      tester.view.devicePixelRatio = originalRatio;
      tester.view.resetPhysicalSize();
    });
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(const MaterialApp(home: LegalScreen(initialTab: 3)));
    await tester.pumpAndSettle();

    expect(find.text('Nos mesures'), findsOneWidget);
  });
}
