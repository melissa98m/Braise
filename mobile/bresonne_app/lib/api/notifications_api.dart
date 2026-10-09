import 'api_client.dart';

class NotificationsApi {
  NotificationsApi(this._client);
  final ApiClient _client;

  Future<String> getVapidPublicKey() async {
    final json = await _client.get('/notifications/vapid-public-key');
    return (json as Map<String, dynamic>)['public_key'] as String;
  }

  Future<void> subscribe({
    required String endpoint,
    required String p256dh,
    required String auth,
    required bool notifyMatch,
    required bool notifyQuestion,
    required bool notifyMessages,
  }) {
    return _client.post(
      '/notifications/subscribe',
      body: {
        'endpoint': endpoint,
        'keys': {'p256dh': p256dh, 'auth': auth},
        'notify_match': notifyMatch,
        'notify_question': notifyQuestion,
        'notify_messages': notifyMessages,
      },
    );
  }

  Future<void> unsubscribe(String endpoint) {
    return _client.delete('/notifications/subscribe?endpoint=${Uri.encodeQueryComponent(endpoint)}');
  }
}
