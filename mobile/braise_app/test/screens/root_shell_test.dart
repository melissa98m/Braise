// RootShell's daily-question reminder (P9.1) is the one notification trigger with no natural
// event to hook into (unlike a match or a message) — it fires once per calendar day on first
// mount, tracked via a SharedPreferences date stamp. These tests mock the 4 endpoints its 3
// eagerly-built tabs (DiscoveryScreen, MatchesListScreen, ProfileTrustScreen — an IndexedStack
// builds all of them at once) need to avoid unrelated error states.

import 'dart:convert';

import 'package:braise_app/notifications/notification_prefs.dart';
import 'package:braise_app/notifications/notifications_service.dart';
import 'package:braise_app/screens/root_shell.dart';
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

MockClient _tabsClient() {
  return MockClient((request) async {
    if (request.method == 'GET' && request.url.path == '/discovery/feed') {
      return _json([], 200);
    }
    if (request.method == 'GET' && request.url.path == '/discovery/matches') {
      return _json([], 200);
    }
    if (request.method == 'GET' && request.url.path == '/profiles/me/public') {
      return _json({
        'display_name': 'Camille',
        'age': 27,
        'bio': 'Bio.',
        'interests': [],
        'avatar': {'seed': 'a', 'from_color': '#FF3366', 'to_color': '#3366FF', 'angle_deg': 0.0},
        'is_published': true,
        'is_premium': false,
        'is_verified': true,
        'gender': null,
        'looking_for_gender': null,
        'age_min': null,
        'age_max': null,
      }, 200);
    }
    if (request.method == 'GET' && request.url.path == '/moderation/me/trust-score') {
      return _json({'score': 50, 'label': 'SOLIDE', 'rating_count': 1, 'flagged_count': 0}, 200);
    }
    return http.Response('not found', 404);
  });
}

Widget _harness(AppServices services) {
  return MultiProvider(
    providers: [Provider<AppServices>.value(value: services)],
    child: const MaterialApp(home: RootShell()),
  );
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('notifies about the daily question on first mount (default preference on)', (
    tester,
  ) async {
    String? notifiedTitle;
    final services = AppServices(
      httpClient: _tabsClient(),
      notificationsService: NotificationsService(
        notify: ({required String title, String? body}) => notifiedTitle = title,
      ),
    );

    await tester.pumpWidget(_harness(services));
    await tester.pumpAndSettle();

    expect(notifiedTitle, 'Question du jour disponible');
  });

  testWidgets('does not notify again for a second mount on the same day', (tester) async {
    var notifyCount = 0;
    final services = AppServices(
      httpClient: _tabsClient(),
      notificationsService: NotificationsService(notify: ({required title, body}) => notifyCount++),
    );

    await tester.pumpWidget(_harness(services));
    await tester.pumpAndSettle();
    expect(notifyCount, 1);

    // Simule une deuxième ouverture de l'app le même jour (RootShell remonté) : la date déjà
    // persistée dans SharedPreferences doit empêcher une seconde notification.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_harness(services));
    await tester.pumpAndSettle();

    expect(notifyCount, 1);
  });

  testWidgets('does not notify when the "daily question" preference is off', (tester) async {
    SharedPreferences.setMockInitialValues({NotificationPrefs.question: false});
    var notified = false;
    final services = AppServices(
      httpClient: _tabsClient(),
      notificationsService: NotificationsService(notify: ({required title, body}) => notified = true),
    );

    await tester.pumpWidget(_harness(services));
    await tester.pumpAndSettle();

    expect(notified, isFalse);
  });
}
