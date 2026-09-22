// ConsentScreen (RGPD, cahier des charges A.9/CNIL — voir main.dart's _AuthGate et
// otp_screen.dart : tout compte signedIn sans les 4 consentements y est routé avant le reste).
// Couvre : bouton désactivé tant que les 4 cases ne sont pas cochées, soumission complète menant
// à ProfileSetupScreen (profil jamais publié) ou RootShell (profil déjà publié), et une erreur
// réseau qui ne fait pas disparaître le formulaire.

import 'dart:convert';

import 'package:bresonne_app/screens/onboarding/consent_screen.dart';
import 'package:bresonne_app/screens/profile/profile_setup_screen.dart';
import 'package:bresonne_app/state/app_services.dart';
import 'package:bresonne_app/state/auth_controller.dart';
import 'package:bresonne_app/theme/braise_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response _json(Object data, int status) {
  return http.Response(
    jsonEncode(data),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

Map<String, dynamic> _publicProfile({required bool isPublished}) => {
  'display_name': 'Camille',
  'age': 27,
  'bio': '',
  'interests': <String>[],
  'avatar': {'seed': 'abc', 'from_color': '#FF3366', 'to_color': '#3366FF', 'angle_deg': 45.0},
  'is_published': isPublished,
  'is_premium': false,
  'is_verified': true,
  'gender': null,
  'looking_for_gender': null,
  'age_min': null,
  'age_max': null,
};

Widget _harness(AppServices services) {
  return MultiProvider(
    providers: [
      Provider<AppServices>.value(value: services),
      ChangeNotifierProvider<AuthController>.value(value: services.authController),
    ],
    child: MaterialApp(theme: buildBraiseTheme(Brightness.dark), home: const ConsentScreen()),
  );
}

/// ConsentScreen est un `ListView` (4 cases + le cadre dédié à la donnée sensible, du texte
/// long) plus haut que le viewport de test par défaut (800x600) : au-delà du `cacheExtent` du
/// `Sliver` sous-jacent, un enfant n'est simplement pas construit, donc absent de l'arbre
/// d'éléments — `find.byType(ElevatedButton)` renvoie alors 0 résultat même sans jamais avoir
/// scrollé. Même contournement que `profile_trust_screen_test.dart`/`settings_screen_test.dart`
/// pour ce même piège (voir CLAUDE.md) : un viewport de test plus grand plutôt qu'un scroll
/// manuel avant chaque interaction.
Future<void> _useTallViewport(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(400, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Future<void> _checkAllBoxes(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.tap(find.byType(Checkbox).at(i));
    await tester.pump();
  }
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows 4 checkboxes and a disabled continue button until all are checked', (
    tester,
  ) async {
    await _useTallViewport(tester);
    await tester.pumpWidget(_harness(AppServices(httpClient: MockClient((_) async => http.Response('', 404)))));

    expect(find.byType(Checkbox), findsNWidgets(4));
    var button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);

    await _checkAllBoxes(tester);

    button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('unchecking one box after checking all disables continue again', (tester) async {
    await _useTallViewport(tester);
    await tester.pumpWidget(_harness(AppServices(httpClient: MockClient((_) async => http.Response('', 404)))));
    await _checkAllBoxes(tester);

    await tester.tap(find.byType(Checkbox).at(3));
    await tester.pump();

    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('submitting full consent for a never-published profile opens profile setup', (
    tester,
  ) async {
    await _useTallViewport(tester);
    final client = MockClient((request) async {
      if (request.method == 'POST' && request.url.path == '/auth/consent') {
        return _json({'consents_given': true}, 200);
      }
      if (request.method == 'GET' && request.url.path == '/profiles/me/public') {
        return _json(_publicProfile(isPublished: false), 200);
      }
      if (request.method == 'GET' && request.url.path == '/profiles/me/private') {
        return _json({'photos': []}, 200);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await _checkAllBoxes(tester);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    expect(find.byType(ProfileSetupScreen), findsOneWidget);
  });

  testWidgets('a consent submission failure surfaces its message and stays on the screen', (
    tester,
  ) async {
    await _useTallViewport(tester);
    final client = MockClient((request) async {
      if (request.method == 'POST' && request.url.path == '/auth/consent') {
        return _json({'detail': 'Erreur serveur.'}, 500);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await _checkAllBoxes(tester);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    expect(find.text('Erreur serveur.'), findsOneWidget);
    expect(find.byType(ConsentScreen), findsOneWidget);
  });
}
