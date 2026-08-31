// ConceptIntroScreen (A.4.1.5, l'onboarding pédagogique) était sans test. Pas d'appel réseau
// propre à cet écran (juste un PageView à 3 pages) : le seul point délicat est la navigation
// finale vers RootShell, dont les 3 onglets font chacun leur propre GET — non mockés ici, mais
// ça ne crashe plus depuis le correctif ProfileTrustScreen (P7.2) : chaque onglet dégrade
// proprement vers un état d'erreur au lieu de laisser une exception se propager.

import 'package:braise_app/screens/onboarding/concept_intro_screen.dart';
import 'package:braise_app/state/app_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _harness(AppServices services) {
  return MultiProvider(
    providers: [Provider<AppServices>.value(value: services)],
    child: const MaterialApp(home: ConceptIntroScreen()),
  );
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('starts on page 1 of 3 with "Suivant", walks through all 3 pages', (tester) async {
    final client = MockClient((_) async => http.Response('not found', 404));
    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    expect(find.text('Une personnalité avant un visage'), findsOneWidget);
    expect(find.text('Suivant'), findsOneWidget);

    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    expect(find.text('Une question par jour, jamais une épreuve'), findsOneWidget);

    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    expect(find.text('Le profil physique se dévoile ensemble'), findsOneWidget);
    // Dernière page : le bouton change de libellé.
    expect(find.text('Découvrir Braise'), findsOneWidget);
    expect(find.text('Suivant'), findsNothing);
  });

  testWidgets('finishing the last page replaces the screen with the app shell', (tester) async {
    final client = MockClient((_) async => http.Response('not found', 404));
    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Découvrir Braise'));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Découvrir Braise'), findsNothing);
  });
}
