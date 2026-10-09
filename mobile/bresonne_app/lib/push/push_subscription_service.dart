import '../api/notifications_api.dart';
import 'push_platform.dart' as platform;

/// Enveloppe injectable autour du Service Worker/Push API — même motif que
/// `NotificationsService` (voir notifications/notifications_service.dart) : les fonctions
/// plateforme réelles sont remplaçables par des fakes en test, pour que rien ne touche un vrai
/// Service Worker/PushManager hors d'un vrai navigateur.
///
/// Une seule ligne d'abonnement sert les 3 catégories (match/question/messages) : le filtrage par
/// catégorie vit côté serveur (voir backend/app/services/notifications.py), pas dans un cache
/// navigateur — `sync` renvoie donc l'état des 3 préférences à chaque appel plutôt que de gérer un
/// abonnement par catégorie.
class PushSubscriptionService {
  PushSubscriptionService({
    Future<void> Function()? registerServiceWorker,
    Future<({String endpoint, String p256dh, String auth})?> Function(String)? subscribe,
    Future<String?> Function()? unsubscribeAndReturnEndpoint,
    bool Function()? isPermissionGranted,
  }) : _registerServiceWorker = registerServiceWorker ?? platform.registerServiceWorker,
       _subscribe = subscribe ?? platform.subscribe,
       _unsubscribeAndReturnEndpoint =
           unsubscribeAndReturnEndpoint ?? platform.unsubscribeAndReturnEndpoint,
       _isPermissionGranted = isPermissionGranted ?? platform.isNotificationPermissionGranted;

  final Future<void> Function() _registerServiceWorker;
  final Future<({String endpoint, String p256dh, String auth})?> Function(String) _subscribe;
  final Future<String?> Function() _unsubscribeAndReturnEndpoint;
  final bool Function() _isPermissionGranted;

  /// Assure qu'un abonnement push existe pour cet appareil et reflète les 3 préférences
  /// courantes. Ne provoque jamais l'invite de permission (voir isPermissionGranted) — appelant
  /// (SettingsScreen) responsable de l'avoir déjà demandée sur le geste explicite de bascule.
  /// Silencieux sur tout échec (navigateur non supporté, refus, réseau) : un abonnement push
  /// cassé ne doit jamais faire échouer l'écran Paramètres.
  Future<void> sync(
    NotificationsApi api, {
    required bool match,
    required bool question,
    required bool messages,
  }) async {
    if (!_isPermissionGranted()) return;
    try {
      await _registerServiceWorker();
      final vapidPublicKey = await api.getVapidPublicKey();
      final subscription = await _subscribe(vapidPublicKey);
      if (subscription == null) return;
      await api.subscribe(
        endpoint: subscription.endpoint,
        p256dh: subscription.p256dh,
        auth: subscription.auth,
        notifyMatch: match,
        notifyQuestion: question,
        notifyMessages: messages,
      );
    } catch (_) {
      // Best effort, voir docstring de la classe.
    }
  }

  /// Désabonne cet appareil, à la fois navigateur (unsubscribe) et serveur (DELETE) — utilisé à
  /// la déconnexion (voir settings_screen.dart/ban_appeal_screen.dart) : sans ça, un appareil
  /// partagé continuerait de recevoir les push du compte qui vient de se déconnecter.
  Future<void> disable(NotificationsApi api) async {
    final endpoint = await _unsubscribeAndReturnEndpoint();
    if (endpoint == null) return;
    try {
      await api.unsubscribe(endpoint);
    } catch (_) {
      // Best effort : le navigateur est de toute façon déjà désabonné localement.
    }
  }
}
