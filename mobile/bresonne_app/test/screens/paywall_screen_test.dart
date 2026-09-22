// PaywallScreen ("Bresonne+") had the same class of bug as ProfileTrustScreen (P7.2), fixed
// alongside these tests: `_load()` had no try/catch at all, so a transient failure left the
// screen spinning forever with nothing scrollable to recover from. `_activate()`/`_cancel()`
// also silently swallowed errors instead of surfacing them like every other mutating action in
// the app. All three now catch ApiException.

import 'dart:convert';

import 'package:bresonne_app/screens/paywall/paywall_screen.dart';
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

Map<String, dynamic> _status({
  required bool isPremium,
  String? expiresAt,
  bool cancelAtPeriodEnd = false,
}) => {'is_premium': isPremium, 'expires_at': expiresAt, 'cancel_at_period_end': cancelAtPeriodEnd};

/// PaywallScreen a un bouton pinné en bas via Spacer (comme OtpScreen/RatingScreen) : son
/// contenu déborde le viewport de test par défaut (800x600).
Future<void> _useTallViewport(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(400, 1500));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Widget _harness(AppServices services) {
  return MultiProvider(
    providers: [Provider<AppServices>.value(value: services)],
    // _PulsingDiamond ne démarre son AnimationController.repeat() que si
    // `MediaQuery.disableAnimations` est faux (il respecte déjà la préférence de mouvement
    // réduit) — sans ce override, l'animation tourne indéfiniment et `pumpAndSettle` ne se
    // termine jamais (il attend une frame sans animation en cours, qui n'arrive jamais).
    child: MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: const PaywallScreen(),
      ),
    ),
  );
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('a free account sees the activate button', (tester) async {
    await _useTallViewport(tester);
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/subscriptions/me') {
        return _json(_status(isPremium: false), 200);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    expect(find.text('Activer Bresonne+'), findsOneWidget);
    expect(find.text('Résilier'), findsNothing);
  });

  testWidgets('activating shows the confirmation and switches to the active state', (
    tester,
  ) async {
    await _useTallViewport(tester);
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/subscriptions/me') {
        return _json(_status(isPremium: false), 200);
      }
      if (request.method == 'POST' && request.url.path == '/subscriptions/debug-activate') {
        return _json(_status(isPremium: true, expiresAt: '2026-12-31T00:00:00Z'), 200);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Activer Bresonne+'));
    await tester.pumpAndSettle();

    expect(find.text('Bresonne+ activé (stub local — aucun paiement réel).'), findsOneWidget);
    expect(find.text('Actif jusqu\'au 31/12/2026.'), findsOneWidget);
    expect(find.text('Résilier'), findsOneWidget);
  });

  testWidgets(
    'a premium account with cancel_at_period_end shows no resiliation button',
    (tester) async {
      await _useTallViewport(tester);
      final client = MockClient((request) async {
        if (request.method == 'GET' && request.url.path == '/subscriptions/me') {
          return _json(
            _status(isPremium: true, expiresAt: '2026-06-15T00:00:00Z', cancelAtPeriodEnd: true),
            200,
          );
        }
        return http.Response('not found', 404);
      });

      await tester.pumpWidget(_harness(AppServices(httpClient: client)));
      await tester.pumpAndSettle();

      expect(
        find.text('Actif jusqu\'au 15/6/2026 (résilié, pas de renouvellement).'),
        findsOneWidget,
      );
      expect(find.text('Résilier'), findsNothing);
      expect(find.text('Activer Bresonne+'), findsNothing);
    },
  );

  testWidgets('a load failure surfaces an error instead of spinning forever, and recovers', (
    tester,
  ) async {
    await _useTallViewport(tester);
    var callCount = 0;
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/subscriptions/me') {
        callCount++;
        if (callCount == 1) return _json({'detail': 'Service indisponible.'}, 503);
        return _json(_status(isPremium: false), 200);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    expect(find.text('Service indisponible.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.fling(find.byType(ListView), const Offset(0, 500), 2000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(callCount, 2);
    expect(find.text('Activer Bresonne+'), findsOneWidget);
    expect(find.text('Service indisponible.'), findsNothing);
  });

  testWidgets('activation error surfaces as a snackbar instead of vanishing silently', (
    tester,
  ) async {
    await _useTallViewport(tester);
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/subscriptions/me') {
        return _json(_status(isPremium: false), 200);
      }
      if (request.method == 'POST' && request.url.path == '/subscriptions/debug-activate') {
        return _json({'detail': 'Erreur serveur.'}, 500);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Activer Bresonne+'));
    await tester.pumpAndSettle();

    expect(find.text('Erreur serveur.'), findsOneWidget);
    // Toujours en état gratuit — l'échec n'a pas fait basculer l'état localement.
    expect(find.text('Activer Bresonne+'), findsOneWidget);
  });
}
