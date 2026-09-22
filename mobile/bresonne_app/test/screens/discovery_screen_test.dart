// DiscoveryScreen (écran 03) est l'écran le plus fréquenté — feed, swipe, célébration de match —
// et restait sans test direct après P5.2/P6 (c'est en le traversant *indirectement* depuis
// otp_screen_test.dart que le crash de _exitController a été trouvé). Ce fichier couvre le feed
// (chargement, vide, erreur) et les trois issues d'un swipe : retrait simple, match mutuel
// (dialogue de célébration), et refus (ex. 402 limite gratuite, la carte revient à sa place).

import 'dart:convert';

import 'package:bresonne_app/notifications/notification_prefs.dart';
import 'package:bresonne_app/notifications/notifications_service.dart';
import 'package:bresonne_app/screens/discovery/discovery_screen.dart';
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

Map<String, dynamic> _candidate({
  required String userId,
  required String displayName,
  List<String> interests = const ['Cinéma'],
  bool isVerified = false,
  int? trustScore,
  String bio = 'Toujours partante pour une rando.',
}) => {
  'user_id': userId,
  'display_name': displayName,
  'age': 27,
  'bio': bio,
  'interests': interests,
  'avatar': {'seed': userId, 'from_color': '#FF3366', 'to_color': '#3366FF', 'angle_deg': 30.0},
  'common_interests': interests,
  'compatibility_score': 0.5,
  'is_verified': isVerified,
  'trust_score': trustScore,
  'trust_label': trustScore == null ? null : 'SOLIDE',
};

Map<String, dynamic> _matchSummary({required String matchId, required String otherUserId}) => {
  'match_id': matchId,
  'other_user_id': otherUserId,
  'other_display_name': 'Camille',
  'flame_count': 0,
  'unlock_threshold': 5,
  'unlock_pct': 0,
  'blur_stage': 'flou_fort',
  'matched_at': '2026-01-01T00:00:00Z',
};

Widget _harness(AppServices services) {
  return MultiProvider(
    providers: [Provider<AppServices>.value(value: services)],
    child: const MaterialApp(home: DiscoveryScreen()),
  );
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('loads the feed and shows the first candidate plus a preview of the next', (
    tester,
  ) async {
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/discovery/feed') {
        return _json([
          _candidate(userId: 'u1', displayName: 'Camille', isVerified: true, trustScore: 88),
          _candidate(userId: 'u2', displayName: 'Alex'),
        ], 200);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    expect(find.text('Camille · 27'), findsOneWidget);
    expect(find.textContaining('VÉRIFIÉ'), findsOneWidget);
    expect(find.textContaining('CONFIANCE 88'), findsOneWidget);
    // Aperçu du suivant, moins présent (cf. _NextCandidatePreview) mais bien affiché.
    expect(find.text('Alex · 27'), findsOneWidget);
  });

  testWidgets('a candidate with no bio shows a placeholder instead of empty guillemets', (
    tester,
  ) async {
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/discovery/feed') {
        return _json([
          _candidate(userId: 'u1', displayName: 'Camille', bio: ''),
          _candidate(userId: 'u2', displayName: 'Alex', bio: ''),
        ], 200);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    expect(find.text('Cette personne n\'a pas encore écrit de bio.'), findsOneWidget);
    expect(find.text('Pas encore de bio.'), findsOneWidget);
    expect(find.textContaining('«'), findsNothing);
  });

  testWidgets('empty feed shows the "nothing left to discover" message', (tester) async {
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/discovery/feed') {
        return _json([], 200);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    expect(find.textContaining('Plus de profil à découvrir'), findsOneWidget);
  });

  testWidgets('feed load error surfaces its message', (tester) async {
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/discovery/feed') {
        return _json({'detail': 'Service indisponible.'}, 503);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    expect(find.text('Service indisponible.'), findsOneWidget);
  });

  testWidgets('passing on the last candidate empties the feed', (tester) async {
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/discovery/feed') {
        return _json([_candidate(userId: 'u1', displayName: 'Camille')], 200);
      }
      if (request.method == 'POST' && request.url.path == '/discovery/swipe') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['decision'], 'pass');
        return _json({'matched': false}, 200);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Passer'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Plus de profil à découvrir'), findsOneWidget);
  });

  testWidgets('liking and getting matched opens the celebration dialog', (tester) async {
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/discovery/feed') {
        return _json([_candidate(userId: 'u1', displayName: 'Camille')], 200);
      }
      if (request.method == 'POST' && request.url.path == '/discovery/swipe') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['decision'], 'like');
        return _json({'matched': true}, 200);
      }
      if (request.method == 'GET' && request.url.path == '/discovery/matches') {
        return _json([_matchSummary(matchId: 'match-1', otherUserId: 'u1')], 200);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Braise'));
    await tester.pumpAndSettle();

    expect(find.text('Braise commune avec Camille !'), findsOneWidget);
    expect(find.text('Commencer à discuter'), findsOneWidget);

    // Referme le dialogue sans naviguer vers la conversation (hors périmètre de ce test).
    await tester.tap(find.text('Continuer à découvrir'));
    await tester.pumpAndSettle();

    expect(find.text('Braise commune avec Camille !'), findsNothing);
  });

  testWidgets(
    'getting matched fires a browser notification when the "new match" preference is on '
    '(the default)',
    (tester) async {
      final client = MockClient((request) async {
        if (request.method == 'GET' && request.url.path == '/discovery/feed') {
          return _json([_candidate(userId: 'u1', displayName: 'Camille')], 200);
        }
        if (request.method == 'POST' && request.url.path == '/discovery/swipe') {
          return _json({'matched': true}, 200);
        }
        if (request.method == 'GET' && request.url.path == '/discovery/matches') {
          return _json([_matchSummary(matchId: 'match-1', otherUserId: 'u1')], 200);
        }
        return http.Response('not found', 404);
      });
      String? notifiedTitle;
      String? notifiedBody;
      final services = AppServices(
        httpClient: client,
        notificationsService: NotificationsService(
          notify: ({required String title, String? body}) {
            notifiedTitle = title;
            notifiedBody = body;
          },
        ),
      );

      await tester.pumpWidget(_harness(services));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Braise'));
      await tester.pumpAndSettle();

      expect(notifiedTitle, 'Braise commune !');
      expect(notifiedBody, 'Vous avez matché avec Camille.');
    },
  );

  testWidgets('getting matched fires no notification when the preference is off', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({NotificationPrefs.match: false});
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/discovery/feed') {
        return _json([_candidate(userId: 'u1', displayName: 'Camille')], 200);
      }
      if (request.method == 'POST' && request.url.path == '/discovery/swipe') {
        return _json({'matched': true}, 200);
      }
      if (request.method == 'GET' && request.url.path == '/discovery/matches') {
        return _json([_matchSummary(matchId: 'match-1', otherUserId: 'u1')], 200);
      }
      return http.Response('not found', 404);
    });
    var notified = false;
    final services = AppServices(
      httpClient: client,
      notificationsService: NotificationsService(notify: ({required title, body}) => notified = true),
    );

    await tester.pumpWidget(_harness(services));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Braise'));
    await tester.pumpAndSettle();

    expect(notified, isFalse);
    // Le dialogue de célébration, lui, reste indépendant de cette préférence.
    expect(find.text('Braise commune avec Camille !'), findsOneWidget);
  });

  testWidgets('a rejected swipe (402) shows a snackbar and keeps the card in place', (
    tester,
  ) async {
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/discovery/feed') {
        return _json([_candidate(userId: 'u1', displayName: 'Camille')], 200);
      }
      if (request.method == 'POST' && request.url.path == '/discovery/swipe') {
        return _json({'detail': 'Limite de matchs gratuits atteinte.'}, 402);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Braise'));
    await tester.pumpAndSettle();

    expect(find.text('Limite de matchs gratuits atteinte.'), findsOneWidget);
    // La carte de Camille est toujours là, le swipe a été refusé et non consommé.
    expect(find.text('Camille · 27'), findsOneWidget);
  });
}
