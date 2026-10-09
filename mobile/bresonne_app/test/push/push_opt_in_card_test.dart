// PushOptInCard : la pré-permission « à la mobile » en tête d'Échanges. Vérifie qu'elle n'invite
// jamais d'office (seulement sur « Activer »), qu'un « Plus tard » la masque durablement, et
// qu'elle guide l'ajout à l'écran d'accueil sur iPhone au lieu d'une permission impossible.

import 'dart:convert';

import 'package:bresonne_app/notifications/notifications_service.dart';
import 'package:bresonne_app/push/push_availability.dart';
import 'package:bresonne_app/push/push_opt_in_card.dart';
import 'package:bresonne_app/push/push_subscription_service.dart';
import 'package:bresonne_app/state/app_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response _json(Object data, int status) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Widget _harness(AppServices services) => Provider<AppServices>.value(
  value: services,
  child: const MaterialApp(home: Scaffold(body: PushOptInCard())),
);

AppServices _services(
  PushAvailability Function() availability, {
  Future<bool> Function()? requestPermission,
  void Function()? onSubscribe,
}) {
  var granted = false;
  return AppServices(
    httpClient: MockClient((request) async {
      if (request.url.path == '/notifications/vapid-public-key') {
        return _json({'public_key': 'fake-key'}, 200);
      }
      if (request.url.path == '/notifications/subscribe') {
        onSubscribe?.call();
        return _json({'endpoint': 'x'}, 200);
      }
      return http.Response('not found', 404);
    }),
    notificationsService: NotificationsService(
      requestPermission: () async {
        final ok = await (requestPermission ?? () async => true)();
        granted = ok;
        return ok;
      },
      notify: ({required String title, String? body}) {},
    ),
    pushSubscriptionService: PushSubscriptionService(
      availability: () => granted ? PushAvailability.granted : availability(),
      isPermissionGranted: () => granted,
      registerServiceWorker: () async {},
      subscribe: (_) async => (endpoint: 'https://fcm.googleapis.com/x', p256dh: 'p', auth: 'a'),
    ),
  );
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('can ask: shown, and permission is only requested on "Activer"', (tester) async {
    var asked = 0;
    var subscribed = false;
    final services = _services(
      () => PushAvailability.canAsk,
      requestPermission: () async {
        asked++;
        return true;
      },
      onSubscribe: () => subscribed = true,
    );

    await tester.pumpWidget(_harness(services));
    await tester.pumpAndSettle();
    expect(find.text("Ne laissez pas une braise s'éteindre"), findsOneWidget);
    expect(asked, 0);

    await tester.tap(find.text('Activer'));
    await tester.pumpAndSettle();

    expect(asked, 1);
    expect(subscribed, isTrue);
    expect(find.text("Ne laissez pas une braise s'éteindre"), findsNothing);
  });

  testWidgets('"Plus tard" hides the card and keeps it hidden on the next visit', (tester) async {
    final services = _services(() => PushAvailability.canAsk);

    await tester.pumpWidget(_harness(services));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plus tard'));
    await tester.pumpAndSettle();
    expect(find.text("Ne laissez pas une braise s'éteindre"), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_harness(services));
    await tester.pumpAndSettle();
    expect(find.text("Ne laissez pas une braise s'éteindre"), findsNothing);
  });

  testWidgets('iPhone outside the installed app: explains "Sur l\'écran d\'accueil", no Activer', (
    tester,
  ) async {
    final services = _services(() => PushAvailability.needsInstall);

    await tester.pumpWidget(_harness(services));
    await tester.pumpAndSettle();

    expect(find.textContaining("Sur l'écran d'accueil"), findsOneWidget);
    expect(find.text('Activer'), findsNothing);
    expect(find.text('Compris'), findsOneWidget);
  });

  for (final availability in [
    PushAvailability.granted,
    PushAvailability.denied,
    PushAvailability.unsupported,
  ]) {
    testWidgets('hidden when $availability', (tester) async {
      await tester.pumpWidget(_harness(_services(() => availability)));
      await tester.pumpAndSettle();
      expect(find.text("Ne laissez pas une braise s'éteindre"), findsNothing);
    });
  }
}
