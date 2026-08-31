// NotificationsService wraps the real browser Notification API (dart:js_interop, web-only —
// see lib/notifications/notification_platform_web.dart) behind two injectable callbacks, the
// same pattern as ApiClient(httpClient: ...). These tests only exercise the injection wiring
// itself — verifying the real browser call actually shows a notification needs a live browser,
// which flutter test (running on the VM) can't provide; `flutter build web` is what proves the
// dart:js_interop code compiles for the real target (see docs/ROADMAP.md, P9.1).

import 'package:braise_app/notifications/notifications_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('requestPermission delegates to the injected callback', () async {
    var called = false;
    final service = NotificationsService(
      requestPermission: () async {
        called = true;
        return true;
      },
    );

    final granted = await service.requestPermission();

    expect(called, isTrue);
    expect(granted, isTrue);
  });

  test('show delegates to the injected callback with title and body', () {
    String? sentTitle;
    String? sentBody;
    final service = NotificationsService(
      notify: ({required String title, String? body}) {
        sentTitle = title;
        sentBody = body;
      },
    );

    service.show(title: 'Braise commune !', body: 'Vous avez matché avec Camille.');

    expect(sentTitle, 'Braise commune !');
    expect(sentBody, 'Vous avez matché avec Camille.');
  });

  test('show works without a body', () {
    String? sentBody = 'not called';
    final service = NotificationsService(
      notify: ({required String title, String? body}) => sentBody = body,
    );

    service.show(title: 'Titre seul');

    expect(sentBody, isNull);
  });

  test('with no injected callbacks, the real (web-only) platform functions are used', () async {
    // Sous la VM (flutter test), notification_platform.dart résout vers le stub no-op — voir
    // notification_platform_stub.dart — donc ceci ne doit ni planter ni afficher quoi que ce
    // soit, juste renvoyer false.
    final service = NotificationsService();

    final granted = await service.requestPermission();

    expect(granted, isFalse);
  });
}
