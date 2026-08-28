import 'api_client.dart';

class AuthApi {
  AuthApi(this._client);
  final ApiClient _client;

  /// Renvoie le code de debug si DEBUG_OTP=true côté backend (stub gratuit, pas de vrai SMS).
  Future<String?> requestOtp(String phone) async {
    final json = await _client.post('/auth/request-otp', body: {'phone': phone});
    return json['debug_code'] as String?;
  }

  Future<String> verifyOtp(String phone, String code) async {
    final json = await _client.post(
      '/auth/verify-otp',
      body: {'phone': phone, 'code': code},
    );
    return json['access_token'] as String;
  }

  Future<Map<String, dynamic>> me() async {
    return await _client.get('/auth/me') as Map<String, dynamic>;
  }
}
