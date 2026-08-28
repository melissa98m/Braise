import '../api/api_client.dart';
import '../api/auth_api.dart';
import '../api/discovery_api.dart';
import '../api/messaging_api.dart';
import '../api/moderation_api.dart';
import '../api/profiles_api.dart';
import '../api/subscriptions_api.dart';
import 'auth_controller.dart';

/// Bundle de tous les services API + l'état d'auth, construit une seule fois à la racine de
/// l'app et distribué via Provider. Évite que chaque écran construise ses propres clients.
class AppServices {
  factory AppServices() {
    // `late final` + closure : authController n'a pas besoin d'exister au moment où le closure
    // est *créé*, seulement au moment où il est *appelé* (au premier appel API authentifié).
    late final AuthController authController;
    final apiClient = ApiClient(tokenProvider: () => authController.token);
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
  });

  final AuthController authController;
  final ApiClient apiClient;
  final ProfilesApi profilesApi;
  final DiscoveryApi discoveryApi;
  final MessagingApi messagingApi;
  final ModerationApi moderationApi;
  final SubscriptionsApi subscriptionsApi;
}
