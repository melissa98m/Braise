#!/usr/bin/env bash
# Point d'entrée du conteneur. Deux usages :
#   - `docker compose up backup` (pas d'argument) : service long-vivant, sauvegarde immédiate puis
#     une toutes les BACKUP_INTERVAL_SECONDS (24h par défaut). Un échec ponctuel n'arrête pas la
#     boucle — il est simplement loggé, pour rester visible dans `docker compose logs backup` /
#     le monitoring (voir service uptime-kuma).
#   - `docker compose run --rm backup <commande>` (ex. /scripts/test_restore.sh) : exécute cette
#     commande une fois et s'arrête — sans ce cas, l'ENTRYPOINT ignorerait silencieusement tout
#     argument passé à `run` et repartirait toujours sur la boucle ci-dessous.
set -uo pipefail

if [ "$#" -gt 0 ]; then
  exec "$@"
fi

INTERVAL="${BACKUP_INTERVAL_SECONDS:-86400}"

echo "Service de sauvegarde démarré (intervalle : ${INTERVAL}s)."
while true; do
  if ! /scripts/backup.sh; then
    echo "ATTENTION : échec de la sauvegarde à $(date -u +%FT%TZ)" >&2
  fi
  sleep "$INTERVAL"
done
