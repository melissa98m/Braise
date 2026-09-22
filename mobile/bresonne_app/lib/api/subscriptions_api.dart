import '../models/subscription.dart';
import 'api_client.dart';

class SubscriptionsApi {
  SubscriptionsApi(this._client);
  final ApiClient _client;

  Future<SubscriptionStatus> me() async {
    final json = await _client.get('/subscriptions/me');
    return SubscriptionStatus.fromJson(json as Map<String, dynamic>);
  }

  Future<SubscriptionStatus> debugActivate() async {
    final json = await _client.post('/subscriptions/debug-activate');
    return SubscriptionStatus.fromJson(json as Map<String, dynamic>);
  }

  Future<SubscriptionStatus> cancel() async {
    final json = await _client.post('/subscriptions/cancel');
    return SubscriptionStatus.fromJson(json as Map<String, dynamic>);
  }
}
