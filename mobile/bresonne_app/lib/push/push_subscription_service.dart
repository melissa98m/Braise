import 'package:shared_preferences/shared_preferences.dart';

import '../api/notifications_api.dart';
import '../notifications/notification_prefs.dart';
import 'push_availability.dart';
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
    PushAvailability Function()? availability,
    Stream<String> Function()? openMatchRequests,
    String? Function()? takeInitialOpenMatch,
  }) : _registerServiceWorker = registerServiceWorker ?? platform.registerServiceWorker,
       _subscribe = subscribe ?? platform.subscribe,
       _unsubscribeAndReturnEndpoint =
           unsubscribeAndReturnEndpoint ?? platform.unsubscribeAndReturnEndpoint,
       _isPermissionGranted = isPermissionGranted ?? platform.isNotificationPermissionGranted,
       _availability = availability ?? platform.pushAvailability,
       _openMatchRequests = openMatchRequests ?? platform.openMatchRequests,
       _takeInitialOpenMatch = takeInitialOpenMatch ?? platform.takeInitialOpenMatch;

  final Future<void> Function() _registerServiceWorker;
  final Future<({String endpoint, String p256dh, String auth})?> Function(String) _subscribe;
  final Future<String?> Function() _unsubscribeAndReturnEndpoint;
  final bool Function() _isPermissionGranted;
  final PushAvailability Function() _availability;
  final Stream<String> Function() _openMatchRequests;
  final String? Function() _takeInitialOpenMatch;

  PushAvailability get availability => _availability();

  /// Conversations à ouvrir parce qu'on a touché une notification alors que l'app était déjà
  /// ouverte (voir web/push_worker.js) — écouté par RootShell.
  Stream<String> get openMatchRequests => _openMatchRequests();

  /// Conversation à ouvrir parce que l'app vient d'être lancée depuis une notification (`?match=`).
  /// Consommée à la première lecture.
  String? takeInitialOpenMatch() => _takeInitialOpenMatch();

  /// Le « oui » de la carte d'activation (ou du bouton de Paramètres) : demande la permission
  /// système — toujours sur ce geste explicite, jamais d'office — puis abonne cet appareil avec
  /// les préférences courantes. `true` si les notifications sont effectivement actives ensuite.
  Future<bool> enable(NotificationsApi api, Future<bool> Function() requestPermission) async {
    if (!await requestPermission()) return false;
    await syncFromPrefs(api);
    return true;
  }

  /// `sync` avec les 3 préférences telles qu'enregistrées (ou leurs valeurs par défaut) — appelé
  /// au démarrage quand la permission est déjà accordée : un appareil sur lequel on vient de se
  /// (re)connecter retrouve ses notifications sans repasser par Paramètres.
  Future<void> syncFromPrefs(NotificationsApi api) async {
    final prefs = await SharedPreferences.getInstance();
    bool pref(String key) => prefs.getBool(key) ?? NotificationPrefs.defaultFor(key);
    await sync(
      api,
      match: pref(NotificationPrefs.match),
      question: pref(NotificationPrefs.question),
      messages: pref(NotificationPrefs.messages),
    );
  }

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
