import 'package:shared_preferences/shared_preferences.dart';

/// Clés des 3 préférences de `SettingsScreen` — définies ici (source unique) plutôt que
/// dupliquées comme constantes privées dans l'écran, puisque les points de déclenchement réels
/// (DiscoveryScreen, ConversationScreen, RootShell) doivent lire exactement les mêmes clés que
/// celles que l'utilisateur bascule dans Paramètres.
class NotificationPrefs {
  const NotificationPrefs._();

  static const match = 'braise_notif_match';
  static const question = 'braise_notif_question';
  static const messages = 'braise_notif_messages';

  static Future<bool> isEnabled(String key, {required bool defaultValue}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key) ?? defaultValue;
  }
}
