/// Repli VM — voir `push_platform.dart` et `notifications/notification_platform_stub.dart` pour
/// le même raisonnement appliqué à `notifications/`. Jamais atteint en usage réel (web only).
Future<void> registerServiceWorker() async {}

Future<({String endpoint, String p256dh, String auth})?> subscribe(String vapidPublicKey) async =>
    null;

Future<String?> unsubscribeAndReturnEndpoint() async => null;

bool isNotificationPermissionGranted() => false;
