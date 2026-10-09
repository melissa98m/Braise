import 'api_client.dart';

class AuthApi {
  AuthApi(this._client);
  final ApiClient _client;

  /// Renvoie le code de debug si DEBUG_OTP=true côté backend (dev local : aucun email réel).
  Future<String?> requestOtp(String email) async {
    final json = await _client.post('/auth/request-otp', body: {'email': email});
    return json['debug_code'] as String?;
  }

  Future<String> verifyOtp(String email, String code) async {
    final json = await _client.post(
      '/auth/verify-otp',
      body: {'email': email, 'code': code},
    );
    return json['access_token'] as String;
  }

  Future<Map<String, dynamic>> me() async {
    return await _client.get('/auth/me') as Map<String, dynamic>;
  }

  /// Les 4 consentements RGPD recueillis par [ConsentScreen] (majorité, CGU, confidentialité,
  /// traitement de la donnée sensible orientation/genre) — voir services/consent.py côté
  /// backend, seule source de vérité sur ce qui a effectivement été consenti.
  Future<bool> submitConsent({
    required bool ageConfirmed,
    required bool cguAccepted,
    required bool privacyAcknowledged,
    required bool sensitiveDataConsented,
  }) async {
    final json = await _client.post(
      '/auth/consent',
      body: {
        'age_confirmed': ageConfirmed,
        'cgu_accepted': cguAccepted,
        'privacy_acknowledged': privacyAcknowledged,
        'sensitive_data_consented': sensitiveDataConsented,
      },
    );
    return json['consents_given'] as bool;
  }
}
