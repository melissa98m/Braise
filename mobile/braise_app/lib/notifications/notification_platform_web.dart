import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// L'API `Notification` du navigateur (gratuite, locale, aucun serveur de push/Firebase/APNs —
/// cohérent avec la contrainte du projet, voir CLAUDE.md) affiche une vraie notification système
/// tant que l'onglet est ouvert. Contrairement à une notification push classique, elle ne
/// fonctionne pas si l'onglet est fermé : ce projet n'a pas de Service Worker enregistré pour ça,
/// et en poser un serait un chantier à part entière (voir docs/ROADMAP.md, plan P9).
Future<bool> requestNotificationPermission() async {
  final result = await web.Notification.requestPermission().toDart;
  return result.toDart == 'granted';
}

void showBrowserNotification({required String title, String? body}) {
  if (web.Notification.permission != 'granted') return;
  web.Notification(title, web.NotificationOptions(body: body ?? ''));
}
