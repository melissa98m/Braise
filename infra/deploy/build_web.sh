#!/usr/bin/env bash
# Construit l'app web Flutter pour la bêta/prod, servie par Caddy (infra/deploy/Caddyfile).
# À lancer depuis la racine du dépôt (sur le VPS, ou en local puis copier build/web avec rsync —
# l'image Flutter fait plusieurs Go, inutile de la tirer sur un petit VPS) :
#   bash infra/deploy/build_web.sh
#   rsync -az --delete mobile/bresonne_app/build/web/ bresonne@<ip>:bresonne/mobile/bresonne_app/build/web/
#
# Deux options qu'il ne faut jamais oublier, d'où ce script plutôt qu'une commande à recopier :
# - API_BASE_URL=/api : l'API est sur la même origine que la page, sous /api (lib/api/api_config.dart) ;
# - --no-web-resources-cdn : CanvasKit servi par nous, pas téléchargé chez Google (gstatic) à chaque
#   chargement — sans ça la CSP du Caddyfile bloque le démarrage de l'app (page blanche).
set -euo pipefail

cd "$(dirname "$0")/../.."
docker compose run --rm --entrypoint bash mobile -c '
  set -e
  cd /app/bresonne_app
  flutter pub get
  bash /app/fetch_fallback_fonts.sh
  flutter build web --release --no-web-resources-cdn --dart-define=API_BASE_URL=/api
  chown -R 1000:1000 /app/bresonne_app
'
echo "Build prêt : mobile/bresonne_app/build/web"
