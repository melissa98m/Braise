#!/bin/bash
set -e

# Phase 6 : scaffold Flutter au premier lancement (le dossier arrive vide du repo),
# puis sert la cible web — gratuit, local, aucun émulateur Android/iOS requis.
if [ ! -f /app/bresonne_app/pubspec.yaml ]; then
  flutter create --project-name bresonne_app --org com.bresonne /app/bresonne_app
fi

flutter config --enable-web
cd /app/bresonne_app

# `flutter build web`/`flutter run` font chacun une résolution de dépendances implicite avant de
# compiler, mais dans ce conteneur (pub cache jamais persisté entre redémarrages, voir
# docker-compose.yml) cette résolution implicite s'est avérée intermittente : plusieurs lancements
# ont échoué avec des fichiers de package "introuvables" (provider, vector_math, ...) alors que le
# téléchargement avait pourtant l'air complet — la compilation démarrait avant que tout soit
# effectivement écrit sur disque. Un `flutter pub get` explicite et bloquant avant la commande de
# build élimine cette course, et n'a jamais échoué en pratique (vécu en diagnostiquant ce bug).
flutter pub get

# MOBILE_MODE=serve (bêta-test réseau local, voir README) : `flutter run -d web-server` est un
# serveur de *développement* — il ouvre une connexion WebSocket de debug vers l'outil Flutter pour
# le hot reload, connexion qui échoue silencieusement quand la page est chargée depuis une autre
# origine que celle attendue par le harnais de debug (DWDS), laissant la page blanche : c'est
# exactement ce qui se passait pour un·e testeur·se accédant via l'IP LAN plutôt que localhost.
# Un vrai build de production (`flutter build web`), servi en fichiers statiques sans aucune
# connexion de debug, n'a pas ce problème — c'est aussi ce qu'il faudrait de toute façon pour un
# vrai déploiement (docs/DEPLOYMENT.md), pas seulement un contournement pour la bêta.
if [ "${MOBILE_MODE:-dev}" = "serve" ]; then
  flutter build web
  echo "Bêta (build de production) servie sur http://0.0.0.0:5000 — build/web"
  exec python3 -m http.server 5000 --bind 0.0.0.0 --directory build/web
fi

flutter run -d web-server --web-port 5000 --web-hostname 0.0.0.0
