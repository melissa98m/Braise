#!/usr/bin/env bash
# Test de restauration bout en bout : sauvegarde -> restauration dans une base/bucket jetables ->
# vérification -> nettoyage. C'est la preuve, pas une supposition, que les dumps produits par
# backup.sh sont effectivement restaurables (cahier des charges D.7/D.12 : "sauvegardes
# automatisées et testées"). À lancer manuellement ou en CI :
#   docker compose run --rm backup /scripts/test_restore.sh
set -euo pipefail

SCRATCH_DB="bresonne_restore_test"
SCRATCH_BUCKET="bresonne-photos-restore-test"

cleanup() {
  PGPASSWORD="$POSTGRES_PASSWORD" dropdb -h db -U "$POSTGRES_USER" --if-exists "$SCRATCH_DB" >/dev/null 2>&1 || true
  mc alias set backuptgt "http://${MINIO_ENDPOINT}" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null 2>&1 || true
  mc rb --force "backuptgt/${SCRATCH_BUCKET}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "=== 1/4 — Sauvegarde ==="
/scripts/backup.sh

echo "=== 2/4 — Restauration dans '$SCRATCH_DB' / '$SCRATCH_BUCKET' ==="
cleanup  # au cas où un run précédent aurait été interrompu avant son propre nettoyage
/scripts/restore.sh "$SCRATCH_DB" "$SCRATCH_BUCKET"

echo "=== 3/4 — Vérification ==="
SRC_COUNT="$(PGPASSWORD="$POSTGRES_PASSWORD" psql -h db -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "SELECT count(*) FROM users")"
DST_COUNT="$(PGPASSWORD="$POSTGRES_PASSWORD" psql -h db -U "$POSTGRES_USER" -d "$SCRATCH_DB" -tAc "SELECT count(*) FROM users")"
if [ "$SRC_COUNT" != "$DST_COUNT" ]; then
  echo "ÉCHEC : table users — source=$SRC_COUNT restaurée=$DST_COUNT" >&2
  exit 1
fi
echo "OK : table users identique entre source et restauration ($SRC_COUNT lignes)."

SRC_OBJ_COUNT="$(find "${BACKUP_DIR:-/backups}/photos" -type f | wc -l)"
DST_OBJ_COUNT="$(mc ls --recursive "backuptgt/${SCRATCH_BUCKET}" 2>/dev/null | wc -l)"
if [ "$SRC_OBJ_COUNT" != "$DST_OBJ_COUNT" ]; then
  echo "ÉCHEC : photos — miroir=$SRC_OBJ_COUNT restaurées=$DST_OBJ_COUNT" >&2
  exit 1
fi
echo "OK : $DST_OBJ_COUNT photo(s) restaurée(s), identique au miroir de sauvegarde."

echo "=== 4/4 — Nettoyage (base et bucket jetables) ==="
# fait par le trap cleanup à la sortie

echo "=== Test de restauration réussi ==="
