#!/usr/bin/env bash
# Sauvegarde Postgres (pg_dump, format custom) + réplication des photos MinIO, avec purge des
# dumps trop anciens. Appelé en boucle par entrypoint.sh, ou directement pour une sauvegarde à la
# demande : `docker compose run --rm backup /scripts/backup.sh`.
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/backups}"
DB_DIR="$BACKUP_DIR/db"
PHOTOS_DIR="$BACKUP_DIR/photos"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-14}"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"

mkdir -p "$DB_DIR" "$PHOTOS_DIR"

echo "[$TIMESTAMP] Dump Postgres ($POSTGRES_DB)..."
DUMP_PATH="$DB_DIR/braise_${TIMESTAMP}.dump"
PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -h db -U "$POSTGRES_USER" -d "$POSTGRES_DB" -F c -f "$DUMP_PATH"
echo "[$TIMESTAMP] Dump écrit : $DUMP_PATH ($(du -h "$DUMP_PATH" | cut -f1))"

echo "[$TIMESTAMP] Purge des dumps de plus de ${RETENTION_DAYS} jours..."
find "$DB_DIR" -name 'braise_*.dump' -mtime +"$RETENTION_DAYS" -print -delete

echo "[$TIMESTAMP] Réplication des photos MinIO ($MINIO_BUCKET)..."
mc alias set backupsrc "http://${MINIO_ENDPOINT}" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null
mc mirror --quiet --remove "backupsrc/${MINIO_BUCKET}" "$PHOTOS_DIR"
echo "[$TIMESTAMP] Photos répliquées vers $PHOTOS_DIR ($(find "$PHOTOS_DIR" -type f | wc -l) objets)."

echo "[$TIMESTAMP] Sauvegarde terminée."

# Ce volume ($BACKUP_DIR, monté sur backup_data) reste local à l'hôte Docker : c'est la même
# limite que pour le reste de la stack en dev (voir CLAUDE.md). En production sur le VPS
# recommandé (cahier des charges D.7), il faut en plus synchroniser ce dossier vers un second
# emplacement physique (ex. Hetzner Storage Box via rclone/rsync) pour que la sauvegarde survive
# à la perte du serveur lui-même — ajouter cette synchronisation ici, sans changer le format des
# dumps ni le script de restauration.
