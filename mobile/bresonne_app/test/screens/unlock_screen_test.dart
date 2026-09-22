// UnlockScreen (écran 05, le payoff du mécanisme flammes) was untested. Deliberately not testing
// the "photos present" case: the photo grid uses Image.network, which would hit the real network
// inside the test sandbox (no network access there) and fail loudly — the empty-photos and error
// states already exercise everything _load() actually branches on.

import 'dart:convert';

import 'package:bresonne_app/models/discovery.dart';
import 'package:bresonne_app/screens/unlock/unlock_screen.dart';
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

Widget _harness(AppServices services) {
  return MultiProvider(
    providers: [Provider<AppServices>.value(value: services)],
    child: MaterialApp(home: UnlockScreen(match: _match)),
  );
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('no private photo yet shows the "nothing added" message', (tester) async {
    final client = MockClient((request) async {
      if (request.method == 'GET' &&
          request.url.path == '/profiles/matches/${_match.matchId}/partner-photos') {
        return _json({'photos': []}, 200);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    expect(find.text('Camille n\'a pas encore ajouté de photo privée.'), findsOneWidget);
    expect(find.text('Noter cet échange'), findsOneWidget);
    expect(find.text('Signaler un problème'), findsOneWidget);
  });

  testWidgets('a load error (not yet unlocked) surfaces its message', (tester) async {
    final client = MockClient((request) async {
      if (request.method == 'GET' &&
          request.url.path == '/profiles/matches/${_match.matchId}/partner-photos') {
        return _json({'detail': 'Ce match n\'est pas encore débloqué.'}, 403);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    expect(find.text('Ce match n\'est pas encore débloqué.'), findsOneWidget);
    expect(find.text('Noter cet échange'), findsNothing);
  });
}
