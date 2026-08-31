/// Implémentation de repli pour toute cible qui n'est pas le web (VM utilisée par `flutter
/// test`/`flutter analyze`, et toute future cible native) — voir `notification_platform.dart`
/// pour le choix conditionnel entre ce fichier et `notification_platform_web.dart`. Ce projet ne
/// sert jamais l'app ailleurs qu'en Flutter web (voir CLAUDE.md), donc ce stub n'est là que pour
/// que le code compile sous la VM ; il ne sera jamais atteint en usage réel.
Future<bool> requestNotificationPermission() async => false;

void showBrowserNotification({required String title, String? body}) {}
