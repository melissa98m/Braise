import '../models/moderation.dart';
import 'api_client.dart';

class ModerationApi {
  ModerationApi(this._client);
  final ApiClient _client;

  Future<RatingResult> rate(String matchId, int score, String comment) async {
    final json = await _client.post(
      '/moderation/matches/$matchId/rating',
      body: {'score': score, 'comment': comment},
    );
    return RatingResult.fromJson(json as Map<String, dynamic>);
  }

  Future<void> report(String matchId, String reason, String? comment) async {
    await _client.post(
      '/moderation/matches/$matchId/report',
      body: {'reason': reason, if (comment != null) 'comment': comment},
    );
  }

  Future<TrustScore> getTrustScore() async {
    final json = await _client.get('/moderation/me/trust-score');
    return TrustScore.fromJson(json as Map<String, dynamic>);
  }

  /// Seuls appels qu'un compte banni peut encore faire (cahier des charges A.9) — voir
  /// get_current_user_even_if_banned côté backend.
  Future<BanAppeal> fileBanAppeal(String message) async {
    final json = await _client.post('/moderation/ban-appeal', body: {'message': message});
    return BanAppeal.fromJson(json as Map<String, dynamic>);
  }

  Future<List<BanAppeal>> getMyBanAppeals() async {
    final json = await _client.get('/moderation/ban-appeal/mine');
    return (json as List).map((e) => BanAppeal.fromJson(e as Map<String, dynamic>)).toList();
  }
}
