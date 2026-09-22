// BanAppealScreen (P1.1, cahier des charges A.9) n'avait aucune couverture de test avant P5.2 —
// c'est pourtant le seul recours d'un compte banni, donc l'écran le plus dommageable à casser en
// silence. Construit sur l'infra de mock HTTP ajoutée en P3 (AppServices(httpClient: ...)).

import 'dart:convert';

import 'package:bresonne_app/screens/moderation/ban_appeal_screen.dart';
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

/// `http.Response(String, ...)` choisit l'encodage du corps depuis l'en-tête Content-Type
/// (`package:http`, pas un choix de ce projet) : sans lui, il retombe sur Latin-1, ce qui casse
/// le `utf8.decode` côté `ApiClient._decode` (français partout dans cette app, donc des accents
/// partout) avec un `FormatException` confus plutôt qu'une erreur HTTP propre. D'où ce helper
/// plutôt que `http.Response(jsonEncode(...), status)` répété (piège vécu en écrivant ce fichier).
http.Response _json(Object data, int status) {
  return http.Response(
    jsonEncode(data),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

Widget _harness(AppServices services) {
  return MultiProvider(
    providers: [
      Provider<AppServices>.value(value: services),
      ChangeNotifierProvider<AuthController>.value(value: services.authController),
    ],
    child: MaterialApp(
      theme: buildBraiseTheme(Brightness.dark),
      home: const BanAppealScreen(),
    ),
  );
}

http.Response _appealsResponse(List<Map<String, dynamic>> appeals) {
  return _json(appeals, 200);
}

Map<String, dynamic> _pendingAppeal({String message = 'Contestation déjà déposée.'}) => {
  'id': 'appeal-1',
  'status': 'pending',
  'message': message,
  'created_at': '2026-01-01T00:00:00Z',
  'decided_at': null,
  'decision_note': null,
};

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('no existing appeal -> shows the filing form', (tester) async {
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/moderation/ban-appeal/mine') {
        return _appealsResponse([]);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    expect(find.text('Envoyer ma contestation'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('too-short message is rejected locally, API never called', (tester) async {
    var postCalled = false;
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/moderation/ban-appeal/mine') {
        return _appealsResponse([]);
      }
      if (request.method == 'POST') postCalled = true;
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    // "court" fait 5 caractères — sous les 10 minimum exigés par l'écran (message.length < 10).
    await tester.enterText(find.byType(TextField), 'court');
    await tester.tap(find.text('Envoyer ma contestation'));
    await tester.pumpAndSettle();

    expect(postCalled, isFalse);
    expect(find.textContaining('10 caractères'), findsOneWidget);
  });

  testWidgets('successful submission replaces the form with the pending status', (tester) async {
    const message = 'Je conteste ce bannissement, ce n\'est pas justifié du tout.';
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/moderation/ban-appeal/mine') {
        return _appealsResponse([]);
      }
      if (request.method == 'POST' && request.url.path == '/moderation/ban-appeal') {
        return _json(_pendingAppeal(message: message), 201);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), message);
    await tester.tap(find.text('Envoyer ma contestation'));
    await tester.pumpAndSettle();

    expect(find.text('EN COURS D\'EXAMEN'), findsOneWidget);
    expect(find.textContaining(message), findsOneWidget);
    expect(find.text('Envoyer ma contestation'), findsNothing);
  });

  testWidgets('existing pending appeal on load -> status shown, no form', (tester) async {
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/moderation/ban-appeal/mine') {
        return _appealsResponse([_pendingAppeal()]);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    expect(find.text('EN COURS D\'EXAMEN'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Envoyer ma contestation'), findsNothing);
  });

  testWidgets('overturned appeal lets the user file a new one', (tester) async {
    final overturned = {
      ..._pendingAppeal(message: 'Première contestation.'),
      'status': 'overturned',
      'decided_at': '2026-01-02T00:00:00Z',
      'decision_note': 'Bannissement levé après revue.',
    };
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/moderation/ban-appeal/mine') {
        return _appealsResponse([overturned]);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    expect(find.text('BANNISSEMENT LEVÉ'), findsOneWidget);
    expect(find.textContaining('Bannissement levé après revue.'), findsOneWidget);
    // Un statut déjà tranché (pas "pending") doit laisser la possibilité de déposer une nouvelle
    // contestation, contrairement au cas "pending" ci-dessus.
    expect(find.text('Envoyer ma contestation'), findsOneWidget);
  });
}
