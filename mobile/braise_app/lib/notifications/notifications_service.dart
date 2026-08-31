import 'notification_platform.dart' as platform;

/// Enveloppe fine autour de l'API `Notification` du navigateur (voir `notification_platform.dart`
/// pour le pourquoi de l'indirection). Les deux fonctions réelles sont injectables — même motif
/// que `ApiClient(httpClient: ...)` — pour que les tests d'écran vérifient "au bon moment, avec le
/// bon message" sans jamais toucher une vraie API navigateur ni dépendre d'une permission
/// utilisateur réellement accordée.
class NotificationsService {
  NotificationsService({
    Future<bool> Function()? requestPermission,
    void Function({required String title, String? body})? notify,
  }) : _requestPermission = requestPermission ?? platform.requestNotificationPermission,
       _notify = notify ?? platform.showBrowserNotification;

  final Future<bool> Function() _requestPermission;
  final void Function({required String title, String? body}) _notify;

  Future<bool> requestPermission() => _requestPermission();

  void show({required String title, String? body}) => _notify(title: title, body: body);
}
