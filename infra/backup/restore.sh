#!/usr/bin/env bash
# Restaure le dump Postgres le plus récent vers une base cible, et optionnellement le miroir de
# photos vers un bucket MinIO cible.
#
# Usage : restore.sh [base_cible] [bucket_cible]
#   - base_cible   : par défaut $POSTGRES_DB (la base réelle — restauration en place, destructif).
#                    Passer un autre nom (ex. bresonne_restore_test) pour restaurer à côté sans
#                    toucher aux données courantes, ce que fait test_restore.sh.
#   - bucket_cible : si fourni, restaure aussi les photos dans ce bucket (créé si absent).
#                    Omis par défaut car restaurer par-dessus le bucket réel doit être un choix
#                    explicite, pas un effet de bord de ce script.
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/backups}"
DB_DIR="$BACKUP_DIR/db"
PHOTOS_DIR="$BACKUP_DIR/photos"

TARGET_DB="${1:-$POSTGRES_DB}"
TARGET_BUCKET="${2:-}"

DUMP_FILE="$(ls -t "$DB_DIR"/bresonne_*.dump 2>/dev/null | head -n1)"
if [ -z "$DUMP_FILE" ]; then
  echo "Aucun dump trouvé dans $DB_DIR — lance d'abord backup.sh." >&2
  exit 1
fi

echo "Restauration DB : $DUMP_FILE -> base '$TARGET_DB'"
EXISTS="$(PGPASSWORD="$POSTGRES_PASSWORD" psql -h db -U "$POSTGRES_USER" -d postgres -tAc \
  "SELECT 1 FROM pg_database WHERE datname = '$TARGET_DB'")"
if [ "$EXISTS" != "1" ]; then
  PGPASSWORD="$POSTGRES_PASSWORD" createdb -h db -U "$POSTGRES_USER" "$TARGET_DB"
fi
PGPASSWORD="$POSTGRES_PASSWORD" pg_restore -h db -U "$POSTGRES_USER" -d "$TARGET_DB" \
  --clean --if-exists --no-owner "$DUMP_FILE"
echo "Base '$TARGET_DB' restaurée depuis $DUMP_FILE."

if [ -n "$TARGET_BUCKET" ]; then
  echo "Restauration photos : $PHOTOS_DIR -> bucket '$TARGET_BUCKET'"
  mc alias set backuptgt "http://${MINIO_ENDPOINT}" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null
  mc mb -p "backuptgt/${TARGET_BUCKET}" >/dev/null 2>&1 || true
  mc mirror --quiet "$PHOTOS_DIR" "backuptgt/${TARGET_BUCKET}"
  echo "Photos restaurées dans '$TARGET_BUCKET'."
fi
