// Service Worker dédié au Web Push (voir lib/push/, docs/V2_FEATURES.md §6) — le seul worker de
// l'app : web/flutter_bootstrap.js n'enregistre plus celui de Flutter (déprécié), qui occupait la
// même portée « / » et remplaçait celui-ci à chaque chargement. Minimal et délibérément sans mise
// en cache/offline — ce n'est pas son rôle ici.
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

  const options = {
    body: data.body || '',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    data: { url: data.url || '/' },
  };
  if (data.tag) {
    // Un tag par conversation : un nouveau message remplace la notification précédente de la même
    // conversation au lieu d'en empiler une par message ; `renotify` la fait quand même vibrer.
    options.tag = data.tag;
    options.renotify = true;
  }
  await self.registration.showNotification(data.title || 'Bresonne', options);
}

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(openFromNotification(event.notification.data && event.notification.data.url));
});

// Réutilise l'app déjà ouverte (onglet ou app installée sur l'écran d'accueil) plutôt que d'en
// ouvrir une seconde : on la remet au premier plan et on lui demande d'ouvrir la conversation
// (lib/push/, message « open-match »). Sinon, ouverture sur `/?match=<id>`, lu au démarrage.
async function openFromNotification(rawUrl) {
  const url = new URL(rawUrl || '/', self.location.origin);
  const matchId = url.searchParams.get('match');
  const clientsList = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
  const existing = clientsList.find((c) => new URL(c.url).origin === self.location.origin);
  if (existing) {
    await existing.focus();
    if (matchId) existing.postMessage({ type: 'open-match', matchId });
    return;
  }
  await self.clients.openWindow(url.href);
}
