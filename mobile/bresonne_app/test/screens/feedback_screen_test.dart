// FeedbackScreen : le retour de bêta depuis Paramètres.

import 'dart:convert';

import 'package:bresonne_app/screens/settings/feedback_screen.dart';
import 'package:bresonne_app/state/app_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

http.Response _json(Object data, int status) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Widget _harness(AppServices services) => Provider<AppServices>.value(
  value: services,
  child: MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FeedbackScreen())),
            child: const Text('ouvrir'),
          ),
        ),
      ),
    ),
  ),
);

Future<void> _open(WidgetTester tester, AppServices services) async {
  await tester.binding.setSurfaceSize(const Size(800, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_harness(services));
  await tester.tap(find.text('ouvrir'));
  await tester.pumpAndSettle();
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('sends the chosen category and message, then closes with a thank-you', (tester) async {
    Map<String, dynamic>? sent;
    final services = AppServices(
      httpClient: MockClient((request) async {
        if (request.url.path == '/feedback') {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return _json({'message': 'ok'}, 201);
        }
        return http.Response('not found', 404);
      }),
    );

    await _open(tester, services);
    await tester.tap(find.text('Une idée, une suggestion'));
    await tester.enterText(find.byType(TextField), 'Un mode sombre plus contrasté ?');
    await tester.tap(find.text('Envoyer'));
    await tester.pumpAndSettle();

    expect(sent, {'category': 'idea', 'message': 'Un mode sombre plus contrasté ?', 'context': 'settings'});
    expect(find.byType(FeedbackScreen), findsNothing);
    expect(find.text('Merci ! Votre retour a bien été envoyé.'), findsOneWidget);
  });

  testWidgets('a too-short message is caught before any network call', (tester) async {
    var calls = 0;
    final services = AppServices(
      httpClient: MockClient((request) async {
        calls++;
        return http.Response('not found', 404);
      }),
    );

    await _open(tester, services);
    await tester.enterText(find.byType(TextField), 'ko');
    await tester.tap(find.text('Envoyer'));
    await tester.pumpAndSettle();

    expect(find.text('Dites-nous en un peu plus (quelques mots suffisent).'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('a server error is shown and the screen stays open', (tester) async {
    final services = AppServices(
      httpClient: MockClient(
        (request) async => _json({'detail': "Beaucoup de retours aujourd'hui — merci ! Réessayez demain."}, 429),
      ),
    );

    await _open(tester, services);
    await tester.enterText(find.byType(TextField), 'Encore une idée !');
    await tester.tap(find.text('Envoyer'));
    await tester.pumpAndSettle();

    expect(find.text("Beaucoup de retours aujourd'hui — merci ! Réessayez demain."), findsOneWidget);
    expect(find.byType(FeedbackScreen), findsOneWidget);
  });
}
