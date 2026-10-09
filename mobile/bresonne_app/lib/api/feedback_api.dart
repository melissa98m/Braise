import 'api_client.dart';

/// Retours des testeur·se·s et erreurs remontées par l'app (bêta) — voir
/// backend/app/api/v1/feedback.py. Les deux finissent dans le tableau de bord staff.
class FeedbackApi {
  FeedbackApi(this._client);
  final ApiClient _client;

  /// `category` : 'bug', 'idea' ou 'other'.
  Future<void> sendFeedback({required String category, required String message, String? context}) {
    return _client.post(
      '/feedback',
      body: {'category': category, 'message': message, 'context': ?context},
    );
  }

  /// Fonctionne connecté·e ou non (le jeton est joint s'il existe) — une erreur peut survenir
  /// avant la connexion. `source` : 'flutter' ou 'platform'.
  Future<void> reportError({
    required String message,
    String? stack,
    required String source,
    String? path,
  }) {
    return _client.post(
      '/client-errors',
      body: {'message': message, 'stack': ?stack, 'source': source, 'path': ?path},
    );
  }
}
