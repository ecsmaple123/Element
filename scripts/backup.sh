#!/usr/bin/env bash
# Backs up everything needed to rebuild matrix-hub on another machine:
#   db/globals.sql   Postgres roles (incl. password hashes)
#   db/<name>.dump   one logical dump per database (Synapse + every bridge); CPU-arch independent
#   files.tar.gz     the project folder: configs, .env, git history, data/ (Synapse signing key,
#                    secrets, media; Caddy CA; bridge state). Excludes .docker-data/ and backups/.
#   MANIFEST         versions + Synapse row counts (used to verify a restore)
#   SHA256SUMS
# Keeps the newest $KEEP backups (default 7). Contents are sensitive: secrets, keys, message history.
set -euo pipefail
cd "$(dirname "$0")/.."
export DOCKER_HOST="${DOCKER_HOST:-unix:///run/user/$(id -u)/docker.sock}"
PROJECT="${COMPOSE_PROJECT_NAME:-matrixhub}"
KEEP="${KEEP:-7}"
dc() { docker compose -p "$PROJECT" "$@"; }
psql_() { dc exec -T postgres psql -U postgres -v ON_ERROR_STOP=1 -At "$@"; }

umask 077
mkdir -p backups
OUT="backups/matrix-hub-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT/db"
trap 'echo "Backup FAILED; removing partial $OUT" >&2; rm -rf "$OUT"' ERR

# 1. Databases
dc exec -T postgres pg_dumpall -U postgres --globals-only > "$OUT/db/globals.sql"
for db in $(psql_ -c "select datname from pg_database where not datistemplate and datname <> 'postgres'"); do
  dc exec -T postgres pg_dump -U postgres -Fc "$db" > "$OUT/db/$db.dump"
  # pg_restore --list fails on a truncated/corrupt archive
  dc exec -T postgres pg_restore --list < "$OUT/db/$db.dump" > /dev/null
done

# 2. Files
tar -czf "$OUT/files.tar.gz" --exclude=./.docker-data --exclude=./backups \
    --exclude=./data/synapse/homeserver.pid .

# 3. Manifest
{
  echo "created: $(date -Is)"
  echo "host: $(hostname)  git: $(git rev-parse --short HEAD 2>/dev/null || echo none)"
  echo "images:"; docker compose -p "$PROJECT" config --images | sed 's/^/  /'
  echo "synapse_counts:"
  for t in users devices access_tokens rooms events local_media_repository; do
    echo "  $t: $(psql_ -d synapse -c "select count(*) from $t")"
  done
} > "$OUT/MANIFEST"
(cd "$OUT" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
trap - ERR

# 4. Retention
ls -1d backups/matrix-hub-* | head -n -"$KEEP" | xargs -r rm -rf

echo "Backup OK: $OUT ($(du -sh "$OUT" | cut -f1))"
