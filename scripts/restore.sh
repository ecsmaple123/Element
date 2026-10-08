#!/usr/bin/env bash
# Restores the databases from a backup into THIS project folder, then starts the stack.
# Run it inside a folder created by extracting the backup's files.tar.gz (see PROJECT_NOTES.md).
#   scripts/restore.sh /path/to/backups/matrix-hub-YYYYmmdd-HHMMSS
# Safety: refuses to run if containers of this compose project already exist, so it can
# never overwrite a running hub. Set COMPOSE_PROJECT_NAME to restore side by side.
set -euo pipefail
cd "$(dirname "$0")/.."
BK="$(cd "${1:?usage: restore.sh <backup-dir>}" && pwd)"
export DOCKER_HOST="${DOCKER_HOST:-unix:///run/user/$(id -u)/docker.sock}"
PROJECT="${COMPOSE_PROJECT_NAME:-matrixhub}"
dc() { docker compose -p "$PROJECT" "$@"; }

echo "Checking backup integrity..."
(cd "$BK" && sha256sum --quiet -c SHA256SUMS)

if [[ -n "$(dc ps -a -q)" ]]; then
  echo "Project '$PROJECT' already has containers here. Refusing to restore over it." >&2
  exit 1
fi

echo "Starting a fresh Postgres..."
dc up -d postgres
# A fresh volume runs the init scripts on a temporary server first; wait for the real one.
for _ in $(seq 1 90); do
  if dc logs postgres 2>/dev/null | grep -q "PostgreSQL init process complete" &&
     dc exec -T postgres pg_isready -U postgres -q 2>/dev/null; then break; fi
  sleep 2
done

echo "Restoring roles..."
# Roles created by the init script already exist; those errors are expected and harmless.
dc exec -T postgres psql -U postgres -q < "$BK/db/globals.sql" 2>&1 | grep -v 'already exists' || true

for f in "$BK"/db/*.dump; do
  db="$(basename "$f" .dump)"
  echo "Restoring database $db..."
  dc exec -T postgres pg_restore -U postgres -d postgres --clean --if-exists --create \
     --exit-on-error < "$f"
done

echo "Starting the full stack..."
dc up -d
echo "Restore done. Check: ./hub.sh status"
