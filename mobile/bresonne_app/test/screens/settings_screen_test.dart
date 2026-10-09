// SettingsScreen had two mutating actions with zero error handling: `_exportData()` and
// `_deleteAccount()` would just let a network failure vanish silently — unlike every other
// mutating action in the app, which always surfaces `ApiException.message`. Fixed alongside
// these tests to catch and show it via a SnackBar.

import 'dart:convert';

import 'package:bresonne_app/notifications/notifications_service.dart';
import 'package:bresonne_app/push/push_subscription_service.dart';
import 'package:bresonne_app/screens/onboarding/otp_screen.dart';
import 'package:bresonne_app/screens/settings/settings_screen.dart';
import 'package:bresonne_app/state/app_services.dart';
import 'package:bresonne_app/state/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// Le contenu de SettingsScreen (4 sections + bouton de déconnexion) dépasse largement le
/// viewport de test par défaut (800x600) : au-delà d'un simple hit-test manqué (comme
/// ReportScreen), les éléments trop loin sous la ligne de flottaison ne sont même pas construits
/// par le `Sliver` sous-jacent du `ListView` (au-delà de son `cacheExtent`), donc `find.text` ne
/// les trouve pas du tout — `tester.ensureVisible()` ne peut pas cibler un widget qui n'existe
/// pas encore dans l'arbre. Un viewport assez haut pour que tout tienne évite le problème plutôt
/// que de le contourner.
Future<void> _useTallViewport(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(800, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Widget _harness(AppServices services) {
  return MultiProvider(
    providers: [
      Provider<AppServices>.value(value: services),
      ChangeNotifierProvider<ThemeController>(create: (_) => ThemeController()),
    ],
    child: const MaterialApp(home: SettingsScreen()),
  );
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('no email restored yet shows a dash, notification defaults are respected', (
    tester,
  ) async {
    await _useTallViewport(tester);
    final client = MockClient((_) async => http.Response('not found', 404));

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    expect(find.text('—'), findsOneWidget);
    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    expect(switches.length, 3);
    expect(switches[0].value, isTrue); // Nouveau match
    expect(switches[1].value, isTrue); // Question du jour
    expect(switches[2].value, isFalse); // Messages
  });

  testWidgets('the email is masked, keeping the first letter and the domain', (tester) async {
    await _useTallViewport(tester);
    SharedPreferences.setMockInitialValues({'braise_token': 'token-1'});
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/auth/me') {
        return _json({'id': 'u1', 'email': 'lea@example.com', 'is_verified': true}, 200);
      }
      return http.Response('not found', 404);
    });
    final services = AppServices(httpClient: client);
    await services.authController.restoreSession();

    await tester.pumpWidget(_harness(services));
    await tester.pumpAndSettle();

    expect(find.text('l••@example.com'), findsOneWidget);
  });

  testWidgets('toggling a notification preference persists it', (tester) async {
    await _useTallViewport(tester);
    final client = MockClient((_) async => http.Response('not found', 404));

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch).last); // "Messages", false -> true
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('braise_notif_messages'), isTrue);
  });

  testWidgets('notification rows expose distinct semantics and toggle via the row itself', (
    tester,
  ) async {
    // P14 a11y pass: the 3 rows had no semantics boundary at all, so a screen reader announced
    // all 3 labels/descriptions merged into one block, with no way to tell which switch was
    // which — found by inspecting the live app's accessibility tree, not by reading the code.
    await _useTallViewport(tester);
    final client = MockClient((_) async => http.Response('not found', 404));

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    final matchRow = find.bySemanticsLabel('Nouveau match. Un like réciproque');
    expect(matchRow, findsOneWidget);
    expect(find.bySemanticsLabel('Question du jour. Rappel quotidien'), findsOneWidget);
    final messagesRow = find.bySemanticsLabel('Messages. Nouveaux messages reçus');
    expect(messagesRow, findsOneWidget);

    expect(
      tester.getSemantics(matchRow),
      matchesSemantics(
        label: 'Nouveau match. Un like réciproque',
        hasToggledState: true,
        isToggled: true,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSemantics(messagesRow),
      matchesSemantics(
        label: 'Messages. Nouveaux messages reçus',
        hasToggledState: true,
        isToggled: false,
        hasTapAction: true,
      ),
    );
    // `hasTapAction: true` ci-dessus garantit qu'un lecteur d'écran peut activer la ligne — le
    // comportement réel du bascule (Switch -> préférence persistée) est déjà couvert par "toggling
    // a notification preference persists it" juste au-dessus, inchangé par ce correctif.
  });

  testWidgets('notification rows are reachable via keyboard Tab and toggle with Space', (
    tester,
  ) async {
    // P17 a11y pass : `excludeSemantics` ci-dessus supprimait aussi le focus clavier natif du
    // `Switch` sous-jacent — au clavier seul (sans lecteur d'écran), les 3 lignes devenaient
    // introuvables par tabulation. Trouvé en parcourant l'ordre de tabulation réel de l'app, pas
    // en supposant que le correctif sémantique précédent suffisait à lui seul.
    await _useTallViewport(tester);
    final client = MockClient((_) async => http.Response('not found', 404));

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    final messagesRow = find.bySemanticsLabel('Messages. Nouveaux messages reçus');
    final focusNode = Focus.of(tester.element(messagesRow), scopeOk: true);
    focusNode.requestFocus();
    await tester.pumpAndSettle();
    expect(focusNode.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('braise_notif_messages'), isTrue);
  });

  testWidgets('turning a notification preference on requests browser permission', (
    tester,
  ) async {
    await _useTallViewport(tester);
    final client = MockClient((_) async => http.Response('not found', 404));
    var permissionRequested = false;
    final services = AppServices(
      httpClient: client,
      notificationsService: NotificationsService(
        requestPermission: () async {
          permissionRequested = true;
          return true;
        },
      ),
    );

    await tester.pumpWidget(_harness(services));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch).last); // "Messages", false -> true
    await tester.pumpAndSettle();

    expect(permissionRequested, isTrue);
  });

  testWidgets('turning a notification preference off does not request permission', (
    tester,
  ) async {
    await _useTallViewport(tester);
    final client = MockClient((_) async => http.Response('not found', 404));
    var permissionRequested = false;
    final services = AppServices(
      httpClient: client,
      notificationsService: NotificationsService(
        requestPermission: () async {
          permissionRequested = true;
          return true;
        },
      ),
    );

    await tester.pumpWidget(_harness(services));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch).first); // "Nouveau match", true -> false
    await tester.pumpAndSettle();

    expect(permissionRequested, isFalse);
  });

  testWidgets('turning a notification preference on also syncs the push subscription', (
    tester,
  ) async {
    await _useTallViewport(tester);
    Map<String, dynamic>? postedBody;
    final client = MockClient((request) async {
      if (request.url.path == '/notifications/vapid-public-key') {
        return _json({'public_key': 'fake-key'}, 200);
      }
      if (request.method == 'POST' && request.url.path == '/notifications/subscribe') {
        postedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return _json({'ok': true}, 200);
      }
      return http.Response('not found', 404);
    });
    final services = AppServices(
      httpClient: client,
      notificationsService: NotificationsService(requestPermission: () async => true),
      pushSubscriptionService: PushSubscriptionService(
        isPermissionGranted: () => true,
        registerServiceWorker: () async {},
        subscribe: (_) async =>
            (endpoint: 'https://fcm.googleapis.com/x', p256dh: 'p', auth: 'a'),
      ),
    );

    await tester.pumpWidget(_harness(services));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch).last); // "Messages", false -> true
    await tester.pumpAndSettle();

    expect(postedBody, isNotNull);
    expect(postedBody!['notify_messages'], isTrue);
  });

  testWidgets('signing out disables the push subscription first', (tester) async {
    await _useTallViewport(tester);
    var disableCalled = false;
    final client = MockClient((_) async => http.Response('not found', 404));
    final services = AppServices(
      httpClient: client,
      pushSubscriptionService: PushSubscriptionService(
        unsubscribeAndReturnEndpoint: () async {
          disableCalled = true;
          return null;
        },
      ),
    );

    await tester.pumpWidget(_harness(services));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Se déconnecter'));
    await tester.pumpAndSettle();

    expect(disableCalled, isTrue);
    expect(find.byType(OtpScreen), findsOneWidget);
  });

  testWidgets('exporting data shows the RGPD confirmation', (tester) async {
    await _useTallViewport(tester);
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/auth/me/export') {
        return _json({'ok': true}, 200);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Exporter mes données'));
    await tester.pumpAndSettle();

    expect(
      find.text('Export généré côté serveur (droit à la portabilité, RGPD).'),
      findsOneWidget,
    );
  });

  testWidgets('an export failure surfaces a snackbar instead of vanishing silently', (
    tester,
  ) async {
    await _useTallViewport(tester);
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/auth/me/export') {
        return _json({'detail': 'Erreur serveur.'}, 500);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Exporter mes données'));
    await tester.pumpAndSettle();

    expect(find.text('Erreur serveur.'), findsOneWidget);
  });

  testWidgets('cancelling account deletion makes no API call', (tester) async {
    await _useTallViewport(tester);
    var deleteCalled = false;
    final client = MockClient((request) async {
      if (request.method == 'DELETE') deleteCalled = true;
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Supprimer mon compte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();

    expect(deleteCalled, isFalse);
    expect(find.text('Paramètres'), findsOneWidget);
  });

  testWidgets('confirming account deletion signs out and returns to the OTP screen', (
    tester,
  ) async {
    await _useTallViewport(tester);
    final client = MockClient((request) async {
      if (request.method == 'DELETE' && request.url.path == '/auth/me') {
        return http.Response('', 200);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Supprimer mon compte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();

    expect(find.byType(OtpScreen), findsOneWidget);
  });

  testWidgets('a deletion failure surfaces a snackbar and stays on Settings', (tester) async {
    await _useTallViewport(tester);
    final client = MockClient((request) async {
      if (request.method == 'DELETE' && request.url.path == '/auth/me') {
        return _json({'detail': 'Erreur serveur.'}, 500);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Supprimer mon compte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();

    expect(find.text('Erreur serveur.'), findsOneWidget);
    expect(find.byType(OtpScreen), findsNothing);
    expect(find.text('Paramètres'), findsOneWidget);
  });

  testWidgets('signing out returns to the OTP screen', (tester) async {
    await _useTallViewport(tester);
    final client = MockClient((_) async => http.Response('not found', 404));

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Se déconnecter'));
    await tester.pumpAndSettle();

    expect(find.byType(OtpScreen), findsOneWidget);
  });
}
