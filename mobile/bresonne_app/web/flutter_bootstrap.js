{{flutter_js}}
{{flutter_build_config}}

// Bootstrap personnalisé (gabarit Flutter, voir docs.flutter.dev « web initialization »), pour
// deux raisons :
// - fontFallbackBaseUrl : les polices de secours (caractères absents de nos polices, emoji
//   compris) sont servies par nous depuis /fonts-fallback/ (téléchargées une fois au build par
//   mobile/fetch_fallback_fonts.sh), jamais par fonts.gstatic.com — sinon chaque visiteur
//   envoyait son adresse IP à Google, et la CSP de bêta/prod bloquait ces polices.
// - pas de serviceWorkerSettings : le Service Worker de Flutter (déprécié) s'enregistrait sur la
//   même portée « / » que web/push_worker.js (notifications push). Une portée n'a qu'un worker
//   actif — les deux scripts se remplaçaient à chaque chargement, et une notification push
//   pouvait tomber sur celui de Flutter, qui ne sait pas l'afficher.
_flutter.loader.load({
  config: {
    fontFallbackBaseUrl: "/fonts-fallback/",
  },
});
