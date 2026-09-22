// ReportScreen (extrait de RatingScreen en P1, cahier des charges C.1) n'avait aucune couverture
// de test avant P5.2 malgré 3 points d'entrée (conversation, déblocage, notation) — le genre
// d'écran partagé où une régression silencieuse se répercute partout à la fois.

import 'dart:convert';

import 'package:bresonne_app/models/discovery.dart';
import 'package:bresonne_app/screens/moderation/report_screen.dart';
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

final _match = MatchSummary(
  matchId: 'match-1',
  otherUserId: 'user-2',
  otherDisplayName: 'Camille',
  flameCount: 2,
  unlockThreshold: 5,
  unlockPct: 40,
  blurStage: 'flou_leger',
  matchedAt: DateTime(2026, 1, 1),
);

/// Un `Navigator` réel avec un écran sous ReportScreen — nécessaire pour vérifier le `pop()`
/// après envoi (un `MaterialApp(home: ReportScreen(...))` seul n'aurait rien sous lui).
Widget _harness(AppServices services) {
  return MultiProvider(
    providers: [
      Provider<AppServices>.value(value: services),
      ChangeNotifierProvider<AuthController>.value(value: services.authController),
    ],
    child: MaterialApp(
      theme: buildBraiseTheme(Brightness.dark),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => ReportScreen(match: _match))),
              child: const Text('Ouvrir le signalement'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openReportScreen(WidgetTester tester) async {
  await tester.tap(find.text('Ouvrir le signalement'));
  await tester.pumpAndSettle();
}

/// ReportScreen (5 motifs + texte + bouton) dépasse la hauteur du viewport de test par défaut
/// (800x600) : `tester.tap()` échoue silencieusement (hit-test hors bornes, cf. l'avertissement
/// "outside the bounds of the root of the render tree") sur tout ce qui est sous la ligne de
/// flottaison sans passer par le `SingleChildScrollView` d'abord.
Future<void> _tapAfterScrollingTo(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('submitting without a motif shows an error, API never called', (tester) async {
    var postCalled = false;
    final client = MockClient((request) async {
      if (request.method == 'POST') postCalled = true;
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await _openReportScreen(tester);

    await tester.enterText(find.byType(TextField), 'Comportement déplacé pendant la conversation.');
    await _tapAfterScrollingTo(tester, find.text('Envoyer le signalement'));
    await tester.pumpAndSettle();

    expect(postCalled, isFalse);
    expect(find.text('Choisissez un motif de signalement.'), findsOneWidget);
  });

  testWidgets('motif selected but no description -> rejected locally', (tester) async {
    var postCalled = false;
    final client = MockClient((request) async {
      if (request.method == 'POST') postCalled = true;
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await _openReportScreen(tester);

    await _tapAfterScrollingTo(tester, find.text('Harcèlement'));
    await tester.pump();
    await _tapAfterScrollingTo(tester, find.text('Envoyer le signalement'));
    await tester.pumpAndSettle();

    expect(postCalled, isFalse);
    expect(find.textContaining('Décrivez ce qui s\'est passé'), findsOneWidget);
  });

  testWidgets('valid report is submitted, screen pops, confirmation shown', (tester) async {
    Map<String, dynamic>? sentBody;
    final client = MockClient((request) async {
      if (request.method == 'POST' &&
          request.url.path == '/moderation/matches/${_match.matchId}/report') {
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return _json({
          'id': 'report-1',
          'reason': sentBody!['reason'],
          'status': 'pending',
          'created_at': '2026-01-01T00:00:00Z',
        }, 200);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await _openReportScreen(tester);

    await _tapAfterScrollingTo(tester, find.text('Comportement suspect'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'A insisté pour se voir hors de l\'app.');
    await _tapAfterScrollingTo(tester, find.text('Envoyer le signalement'));
    await tester.pumpAndSettle();

    expect(sentBody, isNotNull);
    expect(sentBody!['reason'], 'comportement_suspect');
    expect(sentBody!['comment'], 'A insisté pour se voir hors de l\'app.');

    // De retour sur l'écran du dessous (ReportScreen a fait Navigator.pop()) et confirmation
    // affichée.
    expect(find.text('Ouvrir le signalement'), findsOneWidget);
    expect(find.text('Signalement envoyé, merci de votre vigilance.'), findsOneWidget);
  });

  testWidgets('API error surfaces its message and keeps the screen open', (tester) async {
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        return _json({'detail': 'Match introuvable.'}, 404);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await _openReportScreen(tester);

    await _tapAfterScrollingTo(tester, find.text('Autre'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Quelque chose ne va pas dans cet échange.');
    await _tapAfterScrollingTo(tester, find.text('Envoyer le signalement'));
    await tester.pumpAndSettle();

    expect(find.text('Match introuvable.'), findsOneWidget);
    // Toujours sur ReportScreen, pas revenu à l'écran du dessous.
    expect(find.text('Ouvrir le signalement'), findsNothing);
  });
}
