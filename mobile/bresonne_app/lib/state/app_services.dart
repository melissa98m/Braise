import 'package:http/http.dart' as http;

import '../api/api_client.dart';
import '../api/auth_api.dart';
import '../api/discovery_api.dart';
import '../api/messaging_api.dart';
import '../api/moderation_api.dart';
import '../api/notifications_api.dart';
import '../api/profiles_api.dart';
import '../api/subscriptions_api.dart';
import '../notifications/notifications_service.dart';
import '../push/push_subscription_service.dart';
import 'auth_controller.dart';

/// Bundle de tous les services API + l'état d'auth, construit une seule fois à la racine de
/// l'app et distribué via Provider. Évite que chaque écran construise ses propres clients.
class AppServices {
  /// `httpClient` optionnel : `null` en production (chaque écran parle au vrai réseau), un
  /// `MockClient` dans les tests d'écran (voir test/screens/) — c'est ce qui permet de pumper un
  /// écran entier sous un `Provider<AppServices>` sans jamais toucher un vrai serveur.
  /// `notificationsService`/`pushSubscriptionService` optionnels de la même façon : `null` en
  /// production (vraies API navigateur), des callbacks factices dans les tests pour vérifier "au
  /// bon moment, avec le bon message" sans jamais dépendre d'un vrai Service Worker/PushManager.
  factory AppServices({
    http.Client? httpClient,
    NotificationsService? notificationsService,
    PushSubscriptionService? pushSubscriptionService,
  }) {
    // `late final` + closure : authController n'a pas besoin d'exister au moment où le closure
    // est *créé*, seulement au moment où il est *appelé* (au premier appel API authentifié).
    late final AuthController authController;
    final apiClient = ApiClient(tokenProvider: () => authController.token, httpClient: httpClient);
    final authApi = AuthApi(apiClient);
    authController = AuthController(authApi);

    return AppServices._(
      authController: authController,
      apiClient: apiClient,
      profilesApi: ProfilesApi(apiClient),
      discoveryApi: DiscoveryApi(apiClient),
      messagingApi: MessagingApi(apiClient),
      moderationApi: ModerationApi(apiClient),
      subscriptionsApi: SubscriptionsApi(apiClient),
      notificationsApi: NotificationsApi(apiClient),
      notificationsService: notificationsService ?? NotificationsService(),
      pushSubscriptionService: pushSubscriptionService ?? PushSubscriptionService(),
    );
  }

  AppServices._({
    required this.authController,
    required this.apiClient,
    required this.profilesApi,
    required this.discoveryApi,
    required this.messagingApi,
    required this.moderationApi,
    required this.subscriptionsApi,
    required this.notificationsApi,
    required this.notificationsService,
    required this.pushSubscriptionService,
  });

  final AuthController authController;
  final ApiClient apiClient;
  final ProfilesApi profilesApi;
  final DiscoveryApi discoveryApi;
  final MessagingApi messagingApi;
  final ModerationApi moderationApi;
  final SubscriptionsApi subscriptionsApi;
  final NotificationsApi notificationsApi;
  final NotificationsService notificationsService;
  final PushSubscriptionService pushSubscriptionService;
}
