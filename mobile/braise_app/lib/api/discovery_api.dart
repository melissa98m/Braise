import '../models/discovery.dart';
import 'api_client.dart';

class DiscoveryApi {
  DiscoveryApi(this._client);
  final ApiClient _client;

  Future<List<DiscoveryCandidate>> getFeed({int limit = 20}) async {
    final json = await _client.get('/discovery/feed', query: {'limit': '$limit'});
    return (json as List)
        .map((c) => DiscoveryCandidate.fromJson(c as Map<String, dynamic>))
        .toList();
  }

  /// Renvoie `matched` (true si les deux ont liké).
  Future<bool> swipe(String toUserId, String decision) async {
    final json = await _client.post(
      '/discovery/swipe',
      body: {'to_user_id': toUserId, 'decision': decision},
    );
    return (json as Map<String, dynamic>)['matched'] as bool;
  }

  Future<List<MatchSummary>> getMatches() async {
    final json = await _client.get('/discovery/matches');
    return (json as List).map((m) => MatchSummary.fromJson(m as Map<String, dynamic>)).toList();
  }
}
