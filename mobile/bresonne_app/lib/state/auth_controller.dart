import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_exception.dart';
import '../api/auth_api.dart';

enum AuthStatus { unknown, signedOut, signedIn, banned }

/// État d'auth partagé par toute l'app. Le token vit ici (source de vérité) et dans
/// SharedPreferences (persistance entre sessions) — [ApiClient.tokenProvider] lit [token]
/// directement, jamais SharedPreferences à chaque appel.
class AuthController extends ChangeNotifier {
  AuthController(this._authApi);

  static const _tokenKey = 'braise_token';
  // Doit rester le mot pour mot du détail renvoyé par api/deps.py::user_from_token — c'est le
  // seul moyen dont dispose le client de distinguer "banni" (garder le token, router vers la
  // contestation) de "token invalide/expiré/compte supprimé" (déconnexion normale).
  static const _suspendedDetail = 'Compte suspendu.';

  final AuthApi _authApi;

  String? _token;
  String? _userId;
  String? _phone;
  AuthStatus _status = AuthStatus.unknown;
  bool _consentsGiven = false;

  String? get token => _token;
  String? get userId => _userId;
  String? get phone => _phone;
  AuthStatus get status => _status;
  // Reflète `GET /auth/me`'s `consents_given` (voir services/consent.py) — un compte `signedIn`
  // sans les 4 consentements RGPD doit passer par ConsentScreen avant tout le reste, y compris
  // un compte déjà existant qui datait d'avant cette fonctionnalité.
  bool get consentsGiven => _consentsGiven;

  /// Appelé par ConsentScreen une fois `POST /auth/consent` confirmé complet côté serveur —
  /// évite un aller-retour réseau superflu (`me()`) juste pour relire une valeur déjà connue.
  void markConsentsGiven() {
    _consentsGiven = true;
    notifyListeners();
  }

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
      _consentsGiven = me['consents_given'] as bool? ?? false;
      _status = AuthStatus.signedIn;
    } on ApiException catch (e) {
      if (e.isForbidden && e.message == _suspendedDetail) {
        // Compte banni : on garde le token (nécessaire pour appeler /moderation/ban-appeal),
        // contrairement aux autres cas ci-dessous — voir get_current_user_even_if_banned.
        _status = AuthStatus.banned;
      } else {
        // Token expiré, invalide, ou compte supprimé : on repart de zéro plutôt que de laisser
        // l'app dans un état à moitié connecté.
        _token = null;
        await prefs.remove(_tokenKey);
        _status = AuthStatus.signedOut;
      }
    }
    notifyListeners();
  }

  Future<String?> requestOtp(String phone) => _authApi.requestOtp(phone);

  /// Les 4 cases de [ConsentScreen] sont toutes obligatoires pour continuer (bouton désactivé
  /// tant qu'elles ne sont pas cochées) — cette méthode n'est donc appelée qu'une fois les 4 déjà
  /// vraies, jamais avec un sous-ensemble partiel.
  Future<void> submitFullConsent() async {
    final complete = await _authApi.submitConsent(
      ageConfirmed: true,
      cguAccepted: true,
      privacyAcknowledged: true,
      sensitiveDataConsented: true,
    );
    if (complete) markConsentsGiven();
  }

  Future<void> verifyOtp(String phone, String code) async {
    final token = await _authApi.verifyOtp(phone, code);
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    try {
      final me = await _authApi.me();
      _userId = me['id'] as String;
      _phone = me['phone'] as String;
      _consentsGiven = me['consents_given'] as bool? ?? false;
      _status = AuthStatus.signedIn;
    } on ApiException catch (e) {
      // L'OTP réussit même pour un compte banni (services/otp.py ne vérifie pas is_banned) —
      // c'est ici, pas à la vérification du code, qu'il faut le détecter.
      if (!e.isForbidden || e.message != _suspendedDetail) rethrow;
      _status = AuthStatus.banned;
    }
    notifyListeners();
  }

  Future<void> signOut() async {
    _token = null;
    _userId = null;
    _phone = null;
    _consentsGiven = false;
    _status = AuthStatus.signedOut;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    notifyListeners();
  }
}
