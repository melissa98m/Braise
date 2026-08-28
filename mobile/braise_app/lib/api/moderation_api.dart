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

  Future<TrustScore> getTrustScore(String userId) async {
    final json = await _client.get('/moderation/users/$userId/trust-score');
    return TrustScore.fromJson(json as Map<String, dynamic>);
  }
}
