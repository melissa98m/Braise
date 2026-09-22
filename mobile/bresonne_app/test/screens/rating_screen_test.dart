// RatingScreen (écran 06) was untested. Its 5 score chips + comment field + submit button pin
// the button to the bottom via a Spacer (like OtpScreen), so like that screen it can overflow
// the default 800x600 test viewport — enlarging the test surface here is the right fix for the
// same reason it was for OtpScreen, not the ReportScreen situation (no scroll view to hide here).

import 'dart:convert';

import 'package:bresonne_app/models/discovery.dart';
import 'package:bresonne_app/screens/rating/rating_screen.dart';
import 'package:bresonne_app/state/app_services.dart';
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

final _match = MatchSummary(
  matchId: 'match-1',
  otherUserId: 'user-2',
  otherDisplayName: 'Camille',
  flameCount: 5,
  unlockThreshold: 5,
  unlockPct: 100,
  blurStage: 'net',
  matchedAt: DateTime(2026, 1, 1),
);

Future<void> _useTallViewport(WidgetTester tester) async {
  // Comme OtpScreen : 5 puces de score + champ commentaire + encart d'avertissement + bouton
  // pinné en bas via Spacer dépassent largement le viewport de test par défaut (800x600).
  await tester.binding.setSurfaceSize(const Size(400, 1050));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Widget _harness(AppServices services) {
  return MultiProvider(
    providers: [Provider<AppServices>.value(value: services)],
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => RatingScreen(match: _match))),
              child: const Text('Ouvrir la notation'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openRatingScreen(WidgetTester tester) async {
  await tester.tap(find.text('Ouvrir la notation'));
  await tester.pumpAndSettle();
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('a comment under 4 words is rejected locally, API never called', (tester) async {
    await _useTallViewport(tester);
    var postCalled = false;
    final client = MockClient((request) async {
      if (request.method == 'POST') postCalled = true;
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await _openRatingScreen(tester);

    await tester.enterText(find.byType(TextField), 'Trop court');
    await tester.tap(find.text('Envoyer mon avis'));
    await tester.pumpAndSettle();

    expect(postCalled, isFalse);
    expect(find.text('Le commentaire doit contenir au moins 4 mots.'), findsOneWidget);
  });

  testWidgets('a valid rating is submitted with the selected score, screen pops', (tester) async {
    await _useTallViewport(tester);
    Map<String, dynamic>? sentBody;
    final client = MockClient((request) async {
      if (request.method == 'POST' &&
          request.url.path == '/moderation/matches/${_match.matchId}/rating') {
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return _json({
          'score': sentBody!['score'],
          'suspected_rancor': false,
        }, 200);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await _openRatingScreen(tester);

    // Score par défaut 4 ; on choisit explicitement 5 pour vérifier que le choix est bien
    // transmis, pas juste la valeur par défaut.
    await tester.tap(find.text('5'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Une très belle rencontre vraiment.');
    await tester.tap(find.text('Envoyer mon avis'));
    await tester.pumpAndSettle();

    expect(sentBody, isNotNull);
    expect(sentBody!['score'], 5);
    expect(sentBody!['comment'], 'Une très belle rencontre vraiment.');
    expect(find.text('Ouvrir la notation'), findsOneWidget);
    expect(find.text('Avis envoyé, merci.'), findsOneWidget);
  });

  testWidgets('a rating flagged as suspected rancor shows the review-pending message', (
    tester,
  ) async {
    await _useTallViewport(tester);
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        return _json({'score': 1, 'suspected_rancor': true}, 200);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await _openRatingScreen(tester);

    await tester.enterText(find.byType(TextField), 'Ça ne s\'est vraiment pas bien passé.');
    await tester.tap(find.text('Envoyer mon avis'));
    await tester.pumpAndSettle();

    expect(find.text('Avis envoyé — signalé pour revue humaine par prudence.'), findsOneWidget);
  });

  testWidgets('API error surfaces its message and keeps the screen open', (tester) async {
    await _useTallViewport(tester);
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        return _json({'detail': 'Vous avez déjà noté cet échange.'}, 409);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await _openRatingScreen(tester);

    await tester.enterText(find.byType(TextField), 'Un commentaire tout à fait valide.');
    await tester.tap(find.text('Envoyer mon avis'));
    await tester.pumpAndSettle();

    expect(find.text('Vous avez déjà noté cet échange.'), findsOneWidget);
    expect(find.text('Ouvrir la notation'), findsNothing);
  });
}
