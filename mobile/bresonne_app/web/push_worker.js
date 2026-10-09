// Service Worker dédié au Web Push (voir lib/push/, docs/V2_FEATURES.md §6) — un fichier séparé,
// pas une extension du flutter_service_worker.js généré par `flutter build web` : celui-ci s'auto-
// désenregistre au démarrage dans cette version du SDK Flutter (mécanisme de mise en cache déjà
// déprécié), donc rien à y étendre. Minimal et délibérément sans mise en cache/offline — ce n'est
// pas son rôle ici.
//
// Le filtrage par catégorie (match/question/messages) se fait côté serveur (voir
// backend/app/services/notifications.py) : ce worker n'a donc besoin d'aucun stockage local
// (IndexedDB, etc.) pour décider s'il doit afficher une notification par catégorie — la seule
// décision qui lui revient est d'éviter un doublon quand l'app est déjà ouverte et visible (le
// NotificationsService en direct, côté Dart, s'en charge déjà dans ce cas).

self.addEventListener('install', () => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('push', (event) => {
  event.waitUntil(handlePush(event));
});

async function handlePush(event) {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch (e) {
    return;
  }

  const clientsList = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
  const tabVisible = clientsList.some((c) => c.visibilityState === 'visible');
  if (tabVisible) {
    // L'app est déjà ouverte et au premier plan : NotificationsService.show() (Dart, en direct
    // sur le WebSocket/l'appel REST qui vient de se produire) a déjà pu s'en charger — afficher
    // aussi celle-ci ferait doublon.
    return;
  }

  await self.registration.showNotification(data.title || 'Bresonne', {
    body: data.body || '',
    data: { url: data.url || '/' },
  });
}

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = (event.notification.data && event.notification.data.url) || '/';
  event.waitUntil(self.clients.openWindow(url));
});
