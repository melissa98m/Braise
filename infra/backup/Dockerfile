FROM postgres:16-alpine

# postgres:16-alpine ships pg_dump/pg_restore/psql matching the `db` service (docker-compose.yml)
# exactly, which is what pg_dump/pg_restore require to be version-compatible. bash + curl are
# added only for the scripts below and to fetch the MinIO client (mc) — no other tooling needed.
RUN apk add --no-cache bash curl \
    && curl -fsSL https://dl.min.io/client/mc/release/linux-amd64/mc -o /usr/local/bin/mc \
    && chmod +x /usr/local/bin/mc

WORKDIR /scripts
COPY backup.sh restore.sh test_restore.sh entrypoint.sh ./
RUN chmod +x ./*.sh

ENTRYPOINT ["/scripts/entrypoint.sh"]
