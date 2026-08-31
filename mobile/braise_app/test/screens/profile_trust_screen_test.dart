// ProfileTrustScreen ("Moi", l'un des 3 onglets racine) had a real bug fixed alongside these
// tests: `_load()` awaited 3 parallel calls (profile, trust score, matches) with no try/catch —
// a transient error on any of them left `_loading` stuck at `true` forever, with nothing
// scrollable to pull-to-refresh from (RootShell keeps this screen mounted permanently via
// IndexedStack, so `initState` never reruns). Fixed to surface the error and stay refreshable.

import 'dart:convert';

import 'package:braise_app/screens/profile/profile_trust_screen.dart';
import 'package:braise_app/state/app_services.dart';
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

Map<String, dynamic> _publicProfile({bool isVerified = true, bool isPremium = false}) => {
  'display_name': 'Camille',
  'age': 27,
  'bio': 'Toujours partante pour une rando.',
  'interests': ['Cinéma', 'Randonnée'],
  'avatar': {'seed': 'abc', 'from_color': '#FF3366', 'to_color': '#3366FF', 'angle_deg': 45.0},
  'is_published': true,
  'is_premium': isPremium,
  'is_verified': isVerified,
  'gender': 'femme',
  'looking_for_gender': null,
  'age_min': null,
  'age_max': null,
};

Map<String, dynamic> _trustScore({int? score = 88, String? label = 'SOLIDE'}) => {
  'score': score,
  'label': label,
  'rating_count': 4,
  'flagged_count': 0,
};

Map<String, dynamic> _match({required String matchId, int flameCount = 2}) => {
  'match_id': matchId,
  'other_user_id': 'user-$matchId',
  'other_display_name': 'Alex',
  'flame_count': flameCount,
  'unlock_threshold': 5,
  'unlock_pct': 40,
  'blur_stage': 'flou_leger',
  'matched_at': '2026-01-01T00:00:00Z',
};

Widget _harness(AppServices services) {
  return MultiProvider(
    providers: [Provider<AppServices>.value(value: services)],
    child: const MaterialApp(home: ProfileTrustScreen()),
  );
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows the profile, trust score, and aggregated stats once all 3 calls succeed', (
    tester,
  ) async {
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/profiles/me/public') {
        return _json(_publicProfile(isPremium: true), 200);
      }
      if (request.method == 'GET' && request.url.path == '/moderation/me/trust-score') {
        return _json(_trustScore(), 200);
      }
      if (request.method == 'GET' && request.url.path == '/discovery/matches') {
        return _json([
          _match(matchId: 'm1', flameCount: 2),
          _match(matchId: 'm2', flameCount: 3),
        ], 200);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    expect(find.text('Camille'), findsOneWidget);
    expect(find.text('VÉRIFIÉ'), findsOneWidget);
    expect(find.text('BRAISE+'), findsOneWidget);
    expect(find.text('88'), findsOneWidget);
    expect(find.text('SOLIDE'), findsOneWidget);
    // 2 échanges actifs, 5 flammes au total (2+3) mais le badge est plafonné à 5.
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets(
    'a failure on any of the 3 calls surfaces an error instead of spinning forever, '
    'and pull-to-refresh recovers',
    (tester) async {
      var profileCallCount = 0;
      final client = MockClient((request) async {
        if (request.method == 'GET' && request.url.path == '/profiles/me/public') {
          profileCallCount++;
          if (profileCallCount == 1) {
            return _json({'detail': 'Service indisponible.'}, 503);
          }
          return _json(_publicProfile(), 200);
        }
        if (request.method == 'GET' && request.url.path == '/moderation/me/trust-score') {
          return _json(_trustScore(), 200);
        }
        if (request.method == 'GET' && request.url.path == '/discovery/matches') {
          return _json([], 200);
        }
        return http.Response('not found', 404);
      });

      await tester.pumpWidget(_harness(AppServices(httpClient: client)));
      await tester.pumpAndSettle();

      // Avant le correctif, cet écran restait bloqué sur le spinner de chargement indéfiniment.
      expect(find.text('Service indisponible.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.text('Camille'), findsOneWidget);
      expect(find.text('Service indisponible.'), findsNothing);
    },
  );
}
