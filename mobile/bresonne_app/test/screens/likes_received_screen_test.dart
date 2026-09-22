// LikesReceivedScreen (« Qui vous a braisé ») n'avait aucune couverture avant sa création —
// même infra de mock HTTP que les autres tests d'écran (AppServices(httpClient: ...)).

import 'dart:convert';

import 'package:bresonne_app/screens/discovery/likes_received_screen.dart';
import 'package:bresonne_app/screens/paywall/paywall_screen.dart';
import 'package:bresonne_app/state/app_services.dart';
import 'package:bresonne_app/theme/braise_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

/// Même piège que documenté dans ban_appeal_screen_test.dart : sans en-tête content-type,
/// `http.Response(String, ...)` retombe sur Latin-1 et casse `utf8.decode` sur tout accent.
http.Response _json(Object data, int status) {
  return http.Response(
    jsonEncode(data),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

Widget _harness(AppServices services) {
  return MultiProvider(
    providers: [Provider<AppServices>.value(value: services)],
    child: MaterialApp(theme: buildBraiseTheme(Brightness.dark), home: const LikesReceivedScreen()),
  );
}

Map<String, dynamic> _candidate(String id, {String name = 'Camille'}) => {
  'user_id': id,
  'display_name': name,
  'age': 28,
  'bio': 'Bio de test.',
  'interests': ['musique'],
  'avatar': {'seed': 'seed-$id', 'from_color': '#ff0000', 'to_color': '#00ff00', 'angle_deg': 45},
  'common_interests': ['musique'],
  'compatibility_score': 0.5,
  'is_verified': false,
  'trust_score': null,
  'trust_label': null,
};

http.Response _likesReceived({
  required int count,
  required bool isPremium,
  List<Map<String, dynamic>> candidates = const [],
}) {
  return _json({'count': count, 'is_premium': isPremium, 'candidates': candidates}, 200);
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('free tier, no likes -> no upsell CTA', (tester) async {
    final client = MockClient((request) async {
      if (request.url.path == '/discovery/likes-received') {
        return _likesReceived(count: 0, isPremium: false);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    expect(find.textContaining('Personne ne vous a encore braisé'), findsOneWidget);
    expect(find.text('Débloquer avec Bresonne+'), findsNothing);
  });

  testWidgets('free tier with likes -> shows count and upsell CTA to paywall', (tester) async {
    final client = MockClient((request) async {
      if (request.url.path == '/discovery/likes-received') {
        return _likesReceived(count: 3, isPremium: false);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    expect(find.textContaining('3 personnes vous ont déjà braisé'), findsOneWidget);
    expect(find.text('Débloquer avec Bresonne+'), findsOneWidget);

    await tester.tap(find.text('Débloquer avec Bresonne+'));
    await tester.pumpAndSettle();

    expect(find.byType(PaywallScreen), findsOneWidget);
  });

  testWidgets('premium with a candidate -> pass removes the card and decrements count', (
    tester,
  ) async {
    Object? swipeDecision;
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/discovery/likes-received') {
        return _likesReceived(count: 1, isPremium: true, candidates: [_candidate('u1')]);
      }
      if (request.method == 'POST' && request.url.path == '/discovery/swipe') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        swipeDecision = body['decision'];
        return _json({'decision': body['decision'], 'matched': false}, 200);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    expect(find.text('Camille · 28'), findsOneWidget);

    await tester.tap(find.text('Passer'));
    await tester.pumpAndSettle();

    expect(swipeDecision, 'pass');
    expect(find.text('Camille · 28'), findsNothing);
    expect(find.textContaining('Personne ne vous a encore braisé'), findsOneWidget);
  });

  testWidgets('premium liking back with a mutual match -> shows the match dialog', (tester) async {
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/discovery/likes-received') {
        return _likesReceived(count: 1, isPremium: true, candidates: [_candidate('u1')]);
      }
      if (request.method == 'POST' && request.url.path == '/discovery/swipe') {
        return _json({'decision': 'like', 'matched': true}, 200);
      }
      if (request.method == 'GET' && request.url.path == '/discovery/matches') {
        return _json([
          {
            'match_id': 'm1',
            'other_user_id': 'u1',
            'other_display_name': 'Camille',
            'flame_count': 0,
            'unlock_threshold': 5,
            'unlock_pct': 0,
            'blur_stage': 'silhouette',
            'matched_at': '2026-01-01T00:00:00Z',
            'unread_count': 0,
          },
        ], 200);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Braiser en retour'));
    await tester.pumpAndSettle();

    expect(find.text('Braise commune avec Camille !'), findsOneWidget);
  });
}
