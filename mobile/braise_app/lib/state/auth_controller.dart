import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_exception.dart';
import '../api/auth_api.dart';

enum AuthStatus { unknown, signedOut, signedIn }

/// État d'auth partagé par toute l'app. Le token vit ici (source de vérité) et dans
/// SharedPreferences (persistance entre sessions) — [ApiClient.tokenProvider] lit [token]
/// directement, jamais SharedPreferences à chaque appel.
class AuthController extends ChangeNotifier {
  AuthController(this._authApi);

  static const _tokenKey = 'braise_token';

  final AuthApi _authApi;

  String? _token;
  String? _userId;
  String? _phone;
  AuthStatus _status = AuthStatus.unknown;

  String? get token => _token;
  String? get userId => _userId;
  String? get phone => _phone;
  AuthStatus get status => _status;

  Future<void> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_tokenKey);
    if (stored == null) {
      _status = AuthStatus.signedOut;
      notifyListeners();
      return;
    }
    _token = stored;
    try {
      final me = await _authApi.me();
      _userId = me['id'] as String;
      _phone = me['phone'] as String;
      _status = AuthStatus.signedIn;
    } on ApiException {
      // Token expiré, révoqué (banni/supprimé) ou invalide : on repart de zéro plutôt que de
      // laisser l'app dans un état à moitié connecté.
      _token = null;
      await prefs.remove(_tokenKey);
      _status = AuthStatus.signedOut;
    }
    notifyListeners();
  }

  Future<String?> requestOtp(String phone) => _authApi.requestOtp(phone);

  Future<void> verifyOtp(String phone, String code) async {
    final token = await _authApi.verifyOtp(phone, code);
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    final me = await _authApi.me();
    _userId = me['id'] as String;
    _phone = me['phone'] as String;
    _status = AuthStatus.signedIn;
    notifyListeners();
  }

  Future<void> signOut() async {
    _token = null;
    _userId = null;
    _phone = null;
    _status = AuthStatus.signedOut;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    notifyListeners();
  }
}
