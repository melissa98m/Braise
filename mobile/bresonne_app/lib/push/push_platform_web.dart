import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'push_availability.dart';

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

PushAvailability pushAvailability() {
  try {
    final navigator = web.window.navigator as JSObject;
    final supported = navigator.has('serviceWorker') && globalContext.has('PushManager');
    if (!supported) return _isIosBrowserTab() ? PushAvailability.needsInstall : PushAvailability.unsupported;
    return switch (web.Notification.permission) {
      'granted' => PushAvailability.granted,
      'denied' => PushAvailability.denied,
      _ => PushAvailability.canAsk,
    };
  } catch (_) {
    return PushAvailability.unsupported;
  }
}

/// Safari iOS/iPadOS hors app installée : PushManager y est absent tant que l'app n'a pas été
/// ajoutée à l'écran d'accueil. iPadOS se présente comme un Mac — reconnu à son écran tactile.
bool _isIosBrowserTab() {
  final navigator = web.window.navigator;
  final ua = navigator.userAgent;
  final isIos = RegExp('iPhone|iPad|iPod').hasMatch(ua) ||
      (ua.contains('Macintosh') && navigator.maxTouchPoints > 1);
  final standalone = web.window.matchMedia('(display-mode: standalone)').matches ||
      ((navigator as JSObject).getProperty<JSAny?>('standalone'.toJS)?.dartify() == true);
  return isIos && !standalone;
}

StreamController<String>? _openMatchController;

/// Demandes « ouvre cette conversation » envoyées par web/push_worker.js quand on touche une
/// notification alors que l'app est déjà ouverte (elle est remise au premier plan, pas rouverte).
Stream<String> openMatchRequests() {
  final existing = _openMatchController;
  if (existing != null) return existing.stream;
  final controller = StreamController<String>.broadcast();
  _openMatchController = controller;
  try {
    web.window.navigator.serviceWorker.addEventListener(
      'message',
      ((web.MessageEvent event) {
        final data = event.data?.dartify();
        if (data is Map && data['type'] == 'open-match' && data['matchId'] is String) {
          controller.add(data['matchId'] as String);
        }
      }).toJS,
    );
  } catch (_) {
    // Pas de Service Worker : aucune demande ne viendra jamais, le flux reste simplement vide.
  }
  return controller.stream;
}

/// `?match=<id>` quand l'app a été ouverte depuis une notification (web/push_worker.js). Lu une
/// seule fois, puis retiré de l'adresse : un rechargement ne doit pas rouvrir la conversation.
String? takeInitialOpenMatch() {
  final matchId = Uri.base.queryParameters['match'];
  if (matchId == null || matchId.isEmpty) return null;
  try {
    web.window.history.replaceState(null, '', Uri.base.replace(queryParameters: {}).path);
  } catch (_) {}
  return matchId;
}
