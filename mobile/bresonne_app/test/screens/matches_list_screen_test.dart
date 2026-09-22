// MatchesListScreen ("Échanges", l'un des 3 onglets racine) restait sans test malgré une vraie
// logique à couvrir : distinction match débloqué/verrouillé (blurStage), état vide, erreur, et
// tirer-pour-rafraîchir. Contrairement à ConversationScreen (WebSocket réel, pas mockable avec
// l'infra HTTP existante), ce n'est qu'un GET REST — même pattern que discovery_screen_test.dart.

import 'dart:convert';

import 'package:bresonne_app/screens/matches/matches_list_screen.dart';
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

Map<String, dynamic> _match({
  required String matchId,
  required String otherDisplayName,
  required String blurStage,
  int flameCount = 2,
  int unlockThreshold = 5,
  int unlockPct = 40,
  int unreadCount = 0,
}) => {
  'match_id': matchId,
  'other_user_id': 'user-$matchId',
  'other_display_name': otherDisplayName,
  'flame_count': flameCount,
  'unlock_threshold': unlockThreshold,
  'unlock_pct': unlockPct,
  'blur_stage': blurStage,
  'matched_at': '2026-01-01T00:00:00Z',
  'unread_count': unreadCount,
};

Widget _harness(AppServices services) {
  return MultiProvider(
    providers: [Provider<AppServices>.value(value: services)],
    child: const MaterialApp(home: MatchesListScreen()),
  );
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows unlocked and locked matches with distinct subtitles', (tester) async {
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/discovery/matches') {
        return _json([
          _match(matchId: 'm1', otherDisplayName: 'Camille', blurStage: 'net'),
          _match(matchId: 'm2', otherDisplayName: 'Alex', blurStage: 'flou_leger', unlockPct: 40),
        ], 200);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    expect(find.text('Camille'), findsOneWidget);
    expect(find.text('Profil privé débloqué'), findsOneWidget);
    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('Profil privé · 40%'), findsOneWidget);
  });

  testWidgets('shows an unread badge only for matches with unread messages', (tester) async {
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/discovery/matches') {
        return _json([
          _match(
            matchId: 'm1',
            otherDisplayName: 'Camille',
            blurStage: 'net',
            unreadCount: 3,
          ),
          _match(matchId: 'm2', otherDisplayName: 'Alex', blurStage: 'flou_leger'),
        ], 200);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    expect(find.text('3'), findsOneWidget);
    final badges = tester.widgetList<Badge>(find.byType(Badge)).toList();
    expect(badges.where((b) => b.isLabelVisible).length, 1);
  });

  testWidgets('no matches shows the "go discover" message', (tester) async {
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/discovery/matches') {
        return _json([], 200);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    expect(find.textContaining('Pas encore de match'), findsOneWidget);
  });

  testWidgets('load error surfaces its message', (tester) async {
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/discovery/matches') {
        return _json({'detail': 'Service indisponible.'}, 503);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    expect(find.text('Service indisponible.'), findsOneWidget);
  });

  testWidgets('pulling to refresh re-fetches the matches', (tester) async {
    var callCount = 0;
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/discovery/matches') {
        callCount++;
        return _json([], 200);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();
    expect(callCount, 1);

    await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(callCount, 2);
  });
}
