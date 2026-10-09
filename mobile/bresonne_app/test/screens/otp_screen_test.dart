// OtpScreen (écran 01) est le tout premier écran que traverse chaque utilisateur — aucune
// couverture avant ce fichier malgré ça. Contrairement à ReportScreen/BanAppealScreen, il n'y a
// pas de validation locale (le bouton appelle l'API même avec un champ vide) : ce fichier couvre
// donc le flux réseau (demande de code, vérification) et les deux destinations possibles après
// vérification (profil jamais publié -> ProfileSetupScreen, profil publié -> RootShell), plutôt
// que des règles de formulaire qui n'existent pas ici.

import 'dart:convert';

import 'package:bresonne_app/screens/onboarding/consent_screen.dart';
import 'package:bresonne_app/screens/onboarding/otp_screen.dart';
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

/// Voir test/screens/ban_appeal_screen_test.dart pour pourquoi ce helper existe :
/// `http.Response(String, ...)` retombe sur Latin-1 sans en-tête Content-Type explicite, ce qui
/// casse `utf8.decode` côté `ApiClient._decode` dès qu'un accent apparaît (partout, en français).
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
  'bio': 'Toujours partante pour une rando.',
  'interests': ['Cinéma', 'Randonnée'],
  'avatar': {'seed': 'abc', 'from_color': '#FF3366', 'to_color': '#3366FF', 'angle_deg': 45.0},
  'is_published': isPublished,
  'is_premium': false,
  'is_verified': true,
  'gender': 'femme',
  'looking_for_gender': null,
  'age_min': null,
  'age_max': null,
};

/// OtpScreen pin son bouton en bas via un `Spacer` plutôt qu'un `SingleChildScrollView` (le
/// bouton doit rester ancré, cf. ReportScreen qui lui scrolle) : au-delà d'un certain contenu
/// (étape 2, bandeau debug), ça déborde de 1px sur le viewport de test par défaut (800x600), plus
/// court qu'un vrai téléphone. Un vrai écran ne rencontre pas ce cas — élargir le viewport de test
/// ici est correct, contrairement à ReportScreen où masquer le débordement aurait caché un vrai
/// bug de scroll.
Future<void> _useTallViewport(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Widget _harness(AppServices services) {
  return MultiProvider(
    providers: [
      Provider<AppServices>.value(value: services),
      ChangeNotifierProvider<AuthController>.value(value: services.authController),
    ],
    child: MaterialApp(theme: buildBraiseTheme(Brightness.dark), home: const OtpScreen()),
  );
}

/// Route jusqu'à l'étape 2 (code envoyé) via le flux normal : `POST /auth/request-otp` avec
/// `debug_code` renseigné pré-remplit le champ code, exactement comme en dev réel
/// (`DEBUG_OTP=true`, voir CLAUDE.md).
Future<void> _requestCode(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, 'lea@example.com');
  await tester.tap(find.text('Recevoir mon code'));
  await tester.pumpAndSettle();
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('requesting a code pre-fills the debug code and advances to step 2', (
    tester,
  ) async {
    await _useTallViewport(tester);
    final client = MockClient((request) async {
      if (request.method == 'POST' && request.url.path == '/auth/request-otp') {
        return _json({'debug_code': '123456'}, 200);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await _requestCode(tester);

    expect(find.text('2/2'), findsOneWidget);
    expect(find.text('Mode debug local : code pré-rempli (123456).'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('Vérifier le code'), findsOneWidget);
  });

  testWidgets('request-otp error surfaces its message and stays on step 1', (tester) async {
    await _useTallViewport(tester);
    final client = MockClient((request) async {
      if (request.method == 'POST' && request.url.path == '/auth/request-otp') {
        return _json({'detail': 'Trop de demandes de code.'}, 429);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await _requestCode(tester);

    expect(find.text('Trop de demandes de code.'), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('verifying a code for a never-published profile opens profile setup', (
    tester,
  ) async {
    await _useTallViewport(tester);
    final client = MockClient((request) async {
      if (request.method == 'POST' && request.url.path == '/auth/request-otp') {
        return _json({'debug_code': '123456'}, 200);
      }
      if (request.method == 'POST' && request.url.path == '/auth/verify-otp') {
        return _json({'access_token': 'token-1'}, 200);
      }
      if (request.method == 'GET' && request.url.path == '/auth/me') {
        return _json({'id': 'user-1', 'email': 'lea@example.com', 'consents_given': true}, 200);
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
    await _requestCode(tester);
    await tester.tap(find.text('Vérifier le code'));
    await tester.pumpAndSettle();

    expect(find.text('Profil public'), findsOneWidget);
    expect(find.text('On vérifie que vous êtes bien vous.'), findsNothing);
  });

  testWidgets('verifying a code for an already-published profile opens the app shell', (
    tester,
  ) async {
    await _useTallViewport(tester);
    final client = MockClient((request) async {
      if (request.method == 'POST' && request.url.path == '/auth/request-otp') {
        return _json({'debug_code': '123456'}, 200);
      }
      if (request.method == 'POST' && request.url.path == '/auth/verify-otp') {
        return _json({'access_token': 'token-1'}, 200);
      }
      if (request.method == 'GET' && request.url.path == '/auth/me') {
        return _json({'id': 'user-1', 'email': 'lea@example.com', 'consents_given': true}, 200);
      }
      if (request.method == 'GET' && request.url.path == '/profiles/me/public') {
        return _json(_publicProfile(isPublished: true), 200);
      }
      if (request.method == 'GET' && request.url.path == '/discovery/feed') {
        return _json([], 200);
      }
      if (request.method == 'GET' && request.url.path == '/discovery/matches') {
        return _json([], 200);
      }
      if (request.method == 'GET' && request.url.path == '/moderation/me/trust-score') {
        return _json({'score': 88, 'label': 'Fiable', 'rating_count': 4, 'flagged_count': 0}, 200);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await _requestCode(tester);
    await tester.tap(find.text('Vérifier le code'));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('On vérifie que vous êtes bien vous.'), findsNothing);
  });

  testWidgets('verify-otp error surfaces its message and stays on step 2', (tester) async {
    await _useTallViewport(tester);
    final client = MockClient((request) async {
      if (request.method == 'POST' && request.url.path == '/auth/request-otp') {
        return _json({'debug_code': '123456'}, 200);
      }
      if (request.method == 'POST' && request.url.path == '/auth/verify-otp') {
        return _json({'detail': 'Code invalide.'}, 400);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await _requestCode(tester);
    await tester.tap(find.text('Vérifier le code'));
    await tester.pumpAndSettle();

    expect(find.text('Code invalide.'), findsOneWidget);
    expect(find.text('2/2'), findsOneWidget);
  });

  testWidgets('verifying a code for an account with no consent yet opens ConsentScreen', (
    tester,
  ) async {
    await _useTallViewport(tester);
    final client = MockClient((request) async {
      if (request.method == 'POST' && request.url.path == '/auth/request-otp') {
        return _json({'debug_code': '123456'}, 200);
      }
      if (request.method == 'POST' && request.url.path == '/auth/verify-otp') {
        return _json({'access_token': 'token-1'}, 200);
      }
      if (request.method == 'GET' && request.url.path == '/auth/me') {
        return _json({'id': 'user-1', 'email': 'lea@example.com', 'consents_given': false}, 200);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await _requestCode(tester);
    await tester.tap(find.text('Vérifier le code'));
    await tester.pumpAndSettle();

    expect(find.byType(ConsentScreen), findsOneWidget);
  });

  testWidgets('an obviously invalid email is caught before any network call', (tester) async {
    await _useTallViewport(tester);
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'lea-at-example');
    await tester.tap(find.text('Recevoir mon code'));
    await tester.pumpAndSettle();

    expect(find.text('Entrez une adresse email valide, ex. prenom@exemple.fr.'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('"Modifier l\'adresse" goes back to step 1 with the email field editable', (
    tester,
  ) async {
    await _useTallViewport(tester);
    final client = MockClient((request) async {
      if (request.method == 'POST' && request.url.path == '/auth/request-otp') {
        return _json({'message': 'ok', 'debug_code': '123456'}, 200);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await _requestCode(tester);
    expect(find.text('2/2'), findsOneWidget);

    await tester.tap(find.text("Modifier l'adresse ou renvoyer un code"));
    await tester.pumpAndSettle();

    expect(find.text('1/2'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    expect(find.text('Recevoir mon code'), findsOneWidget);
  });
}
