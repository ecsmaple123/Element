#!/usr/bin/env bash
# Creates a Postgres role + database (same name) and prints its connection URI on stdout.
# Usage: scripts/new-db.sh <name>     name: lowercase letters, digits, underscore
set -euo pipefail
cd "$(dirname "$0")/.."
export DOCKER_HOST="${DOCKER_HOST:-unix:///run/user/$(id -u)/docker.sock}"
name="${1:?usage: new-db.sh <name>}"
[[ "$name" =~ ^[a-z][a-z0-9_]*$ ]] || { echo "bad name: $name" >&2; exit 1; }
pw="$(python3 -c 'import secrets; print(secrets.token_hex(24))')"
docker compose exec -T postgres psql -U postgres -v ON_ERROR_STOP=1 -q >/dev/null <<SQL
CREATE ROLE $name LOGIN PASSWORD '$pw';
CREATE DATABASE $name OWNER $name;
SQL
echo "postgres://$name:$pw@postgres/$name?sslmode=disable"
