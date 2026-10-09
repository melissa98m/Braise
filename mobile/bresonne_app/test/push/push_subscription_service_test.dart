// PushSubscriptionService wraps the real Service Worker/Push API (dart:js_interop, web-only —
// see lib/push/push_platform_web.dart) behind injectable callbacks, the same pattern as
// NotificationsService (test/notifications/notifications_service_test.dart). These tests only
// exercise the injection wiring and the sync/disable orchestration logic itself — verifying a
// real subscription reaches a real Service Worker needs a live browser, which flutter test
// (running on the VM) can't provide; `flutter build web` is what proves the dart:js_interop code
// compiles for the real target.

import 'dart:convert';

import 'package:bresonne_app/api/api_client.dart';
import 'package:bresonne_app/api/notifications_api.dart';
import 'package:bresonne_app/push/push_subscription_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response _json(Object data, int status) {
  return http.Response(
    jsonEncode(data),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

void main() {
  test('sync does nothing when permission was never granted (never prompts)', () async {
    var registerCalled = false;
    final service = PushSubscriptionService(
      isPermissionGranted: () => false,
      registerServiceWorker: () async => registerCalled = true,
    );
    final api = NotificationsApi(
      ApiClient(tokenProvider: () => null, httpClient: MockClient((_) async {
        fail('no HTTP call expected when permission was never granted');
      })),
    );

    await service.sync(api, match: true, question: true, messages: false);

    expect(registerCalled, isFalse);
  });

  test('sync short-circuits without calling the API when subscribe returns null', () async {
    var apiCalled = false;
    final service = PushSubscriptionService(
      isPermissionGranted: () => true,
      registerServiceWorker: () async {},
      subscribe: (_) async => null,
    );
    final api = NotificationsApi(
      ApiClient(
        tokenProvider: () => null,
        httpClient: MockClient((request) async {
          apiCalled = true;
          if (request.url.path == '/notifications/vapid-public-key') {
            return _json({'public_key': 'fake-key'}, 200);
          }
          return http.Response('not found', 404);
        }),
      ),
    );

    await service.sync(api, match: true, question: true, messages: false);

    // getVapidPublicKey is expected to be called (needed before subscribe); POST /subscribe must
    // not be, since subscribe() returned null (unsupported browser / permission denied at the
    // Push API level even though Notification permission was granted).
    expect(apiCalled, isTrue);
  });

  test('sync registers, subscribes and posts the subscription with current prefs', () async {
    Map<String, dynamic>? postedBody;
    final service = PushSubscriptionService(
      isPermissionGranted: () => true,
      registerServiceWorker: () async {},
      subscribe: (vapidKey) async {
        expect(vapidKey, 'fake-key');
        return (endpoint: 'https://fcm.googleapis.com/x', p256dh: 'p256dh-value', auth: 'auth-value');
      },
    );
    final api = NotificationsApi(
      ApiClient(
        tokenProvider: () => null,
        httpClient: MockClient((request) async {
          if (request.url.path == '/notifications/vapid-public-key') {
            return _json({'public_key': 'fake-key'}, 200);
          }
          if (request.method == 'POST' && request.url.path == '/notifications/subscribe') {
            postedBody = jsonDecode(request.body) as Map<String, dynamic>;
            return _json({'ok': true}, 200);
          }
          return http.Response('not found', 404);
        }),
      ),
    );

    await service.sync(api, match: true, question: false, messages: true);

    expect(postedBody, isNotNull);
    expect(postedBody!['endpoint'], 'https://fcm.googleapis.com/x');
    expect(postedBody!['keys'], {'p256dh': 'p256dh-value', 'auth': 'auth-value'});
    expect(postedBody!['notify_match'], isTrue);
    expect(postedBody!['notify_question'], isFalse);
    expect(postedBody!['notify_messages'], isTrue);
  });

  test('sync never throws even if the API call fails', () async {
    final service = PushSubscriptionService(
      isPermissionGranted: () => true,
      registerServiceWorker: () async {},
      subscribe: (_) async => (endpoint: 'https://fcm.googleapis.com/x', p256dh: 'a', auth: 'b'),
    );
    final api = NotificationsApi(
      ApiClient(tokenProvider: () => null, httpClient: MockClient((_) async => http.Response('boom', 500))),
    );

    await service.sync(api, match: true, question: true, messages: true);
    // No exception propagated: the test simply completing is the assertion.
  });

  test('disable unsubscribes and deletes the subscription server-side', () async {
    String? deletedEndpointQuery;
    final service = PushSubscriptionService(
      unsubscribeAndReturnEndpoint: () async => 'https://fcm.googleapis.com/x',
    );
    final api = NotificationsApi(
      ApiClient(
        tokenProvider: () => null,
        httpClient: MockClient((request) async {
          if (request.method == 'DELETE' && request.url.path == '/notifications/subscribe') {
            deletedEndpointQuery = request.url.queryParameters['endpoint'];
            return _json({'ok': true}, 200);
          }
          return http.Response('not found', 404);
        }),
      ),
    );

    await service.disable(api);

    expect(deletedEndpointQuery, 'https://fcm.googleapis.com/x');
  });

  test('disable does nothing when there was no existing subscription', () async {
    final service = PushSubscriptionService(unsubscribeAndReturnEndpoint: () async => null);
    final api = NotificationsApi(
      ApiClient(
        tokenProvider: () => null,
        httpClient: MockClient((_) async {
          fail('no HTTP call expected when there is no existing subscription');
        }),
      ),
    );

    await service.disable(api);
  });

  test('enable never subscribes when the permission prompt is refused', () async {
    final service = PushSubscriptionService(
      isPermissionGranted: () => false,
      registerServiceWorker: () async => fail('no registration after a refusal'),
    );
    final api = NotificationsApi(
      ApiClient(tokenProvider: () => null, httpClient: MockClient((_) async {
        fail('no HTTP call after a refusal');
      })),
    );

    expect(await service.enable(api, () async => false), isFalse);
  });

  test('syncFromPrefs sends the stored preferences, defaulting all three to on', () async {
    SharedPreferences.setMockInitialValues({'braise_notif_match': false});
    Map<String, dynamic>? sent;
    final service = PushSubscriptionService(
      isPermissionGranted: () => true,
      registerServiceWorker: () async {},
      subscribe: (_) async => (endpoint: 'https://fcm.googleapis.com/x', p256dh: 'p', auth: 'a'),
    );
    final api = NotificationsApi(
      ApiClient(
        tokenProvider: () => null,
        httpClient: MockClient((request) async {
          if (request.url.path == '/notifications/vapid-public-key') {
            return _json({'public_key': 'fake-key'}, 200);
          }
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return _json({'endpoint': 'x'}, 200);
        }),
      ),
    );

    await service.syncFromPrefs(api);

    expect(sent!['notify_match'], isFalse);
    expect(sent!['notify_question'], isTrue);
    expect(sent!['notify_messages'], isTrue);
  });
}
