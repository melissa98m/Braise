#!/bin/bash
set -e

# Phase 6 : scaffold Flutter au premier lancement (le dossier arrive vide du repo),
# puis sert la cible web — gratuit, local, aucun émulateur Android/iOS requis.
if [ ! -f /app/braise_app/pubspec.yaml ]; then
  flutter create --project-name braise_app --org com.braise /app/braise_app
fi

flutter config --enable-web
cd /app/braise_app
flutter run -d web-server --web-port 5000 --web-hostname 0.0.0.0
