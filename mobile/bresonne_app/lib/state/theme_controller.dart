import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Choix de thème persistant (Système / Clair / Sombre). Sombre reste le réglage par défaut à
/// l'installation (docs/DESIGN_TOKENS.md) — ce contrôleur ajoute juste la bascule volontaire
/// depuis Paramètres, qui manquait à la Phase 6 (ThemeMode figé en dur dans main.dart).
class ThemeController extends ChangeNotifier {
  static const _key = 'braise_theme_mode';

  ThemeMode _mode = ThemeMode.dark;
  ThemeMode get mode => _mode;

  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_key);
    final restored = switch (stored) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.dark,
    };
    if (restored == _mode) return;
    _mode = restored;
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.system => 'system',
      ThemeMode.dark => 'dark',
    });
  }
}
