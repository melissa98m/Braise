#!/usr/bin/env bash
# Télécharge les polices de secours du moteur Flutter web (Noto : symboles, alphabets non latins,
# emoji) dans web/fonts-fallback/, servies ensuite par nous (voir web/flutter_bootstrap.js,
# fontFallbackBaseUrl) plutôt que par fonts.gstatic.com depuis le navigateur de chaque visiteur.
# Le téléchargement a lieu ici, une fois, sur la machine qui construit l'app — jamais chez les
# utilisateur·rice·s.
#
# La liste vient du SDK Flutter lui-même (font_fallback_data.dart du moteur web), donc elle suit
# automatiquement la version de Flutter utilisée. Idempotent : seuls les fichiers manquants sont
# téléchargés (~22 Mo, 725 fichiers la première fois). À lancer dans le conteneur `mobile`.
# Ne fait jamais échouer le build : sans ces polices, un caractère rare s'affiche en carré vide,
# rien de plus.
set -uo pipefail

APP_DIR="${APP_DIR:-/app/bresonne_app}"
DEST="$APP_DIR/web/fonts-fallback"
SDK_DIR="$(dirname "$(dirname "$(readlink -f "$(command -v flutter)")")")"
DATA="$SDK_DIR/engine/src/flutter/lib/web_ui/lib/src/engine/font_fallback_data.dart"

if [ ! -f "$DATA" ]; then
  echo "fetch_fallback_fonts: $DATA introuvable, polices de secours non téléchargées." >&2
  exit 0
fi

mkdir -p "$DEST"
grep -o "[a-z0-9]*/v[0-9]*/[A-Za-z0-9_.-]*\.woff2\?" "$DATA" | sort -u | while read -r path; do
  [ -s "$DEST/$path" ] || echo "$path"
done | xargs -r -P 8 -I{} sh -c 'mkdir -p "$(dirname "$0/{}")" && curl -sfL --retry 2 -o "$0/{}" "https://fonts.gstatic.com/s/{}" || echo "échec : {}" >&2' "$DEST"

echo "Polices de secours prêtes : $(find "$DEST" -type f | wc -l) fichiers dans web/fonts-fallback/"
