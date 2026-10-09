import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Web Push réel (Service Worker + Push API, `package:web`, déjà une dépendance — voir
/// pubspec.yaml) : contrairement à `notifications/notification_platform_web.dart` (notifications
/// navigateur premier-plan uniquement), ceci fonctionne onglet fermé. Chaque fonction avale ses
/// propres erreurs (navigateur sans support, permission refusée, service de push injoignable...)
/// et retourne `null`/ne fait rien plutôt que de lever — jamais casser l'écran Paramètres pour un
/// souci d'abonnement push, même politique que le reste de `notifications/`.
Future<void> registerServiceWorker() async {
  try {
    await web.window.navigator.serviceWorker.register('/push_worker.js'.toJS).toDart;
  } catch (_) {
    // Pas de Service Worker (navigateur non supporté, ou refusé) — silencieux.
  }
}

Future<({String endpoint, String p256dh, String auth})?> subscribe(String vapidPublicKey) async {
  try {
    final registration = await web.window.navigator.serviceWorker.ready.toDart;
    final subscription = await registration.pushManager
        .subscribe(
          web.PushSubscriptionOptionsInit(
            userVisibleOnly: true,
            applicationServerKey: _decodeBase64Url(vapidPublicKey).toJS,
          ),
        )
        .toDart;
    return (
      endpoint: subscription.endpoint,
      p256dh: _encodeBase64UrlKey(subscription, 'p256dh'),
      auth: _encodeBase64UrlKey(subscription, 'auth'),
    );
  } catch (_) {
    return null;
  }
}

Future<String?> unsubscribeAndReturnEndpoint() async {
  try {
    final registration = await web.window.navigator.serviceWorker.ready.toDart;
    final subscription = await registration.pushManager.getSubscription().toDart;
    if (subscription == null) return null;
    final endpoint = subscription.endpoint;
    await subscription.unsubscribe().toDart;
    return endpoint;
  } catch (_) {
    return null;
  }
}

/// Lecture seule, ne provoque jamais l'invite de permission (contrairement à
/// `NotificationsService.requestPermission`) — sert à décider silencieusement si un abonnement
/// push peut être (re)synchronisé sans redemander l'autorisation à chaque bascule de préférence.
bool isNotificationPermissionGranted() => web.Notification.permission == 'granted';

String _encodeBase64UrlKey(web.PushSubscription subscription, String name) {
  final buffer = subscription.getKey(name);
  final bytes = buffer!.toDart.asUint8List();
  return base64Url.encode(bytes).replaceAll('=', '');
}

Uint8List _decodeBase64Url(String value) {
  final padded = value.padRight((value.length + 3) ~/ 4 * 4, '=');
  return base64Url.decode(padded);
}
