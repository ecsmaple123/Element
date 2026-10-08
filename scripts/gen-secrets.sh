#!/usr/bin/env bash
# Creates .env and data/synapse/secrets.yaml with fresh random secrets.
# Refuses to overwrite existing files (losing them would lock you out of the DB).
set -euo pipefail
cd "$(dirname "$0")/.."
umask 077

if [[ -e .env || -e data/synapse/secrets.yaml ]]; then
  echo "Secrets already exist; not overwriting." >&2
  exit 1
fi

rnd() { python3 -c 'import secrets; print(secrets.token_urlsafe(32))'; }
PG=$(rnd); SYN=$(rnd)

cat > .env <<EOF
POSTGRES_PASSWORD=$PG
SYNAPSE_DB_PASSWORD=$SYN
EOF

mkdir -p data/synapse data/caddy
cat > data/synapse/secrets.yaml <<EOF
database:
  name: psycopg2
  args:
    user: synapse
    password: "$SYN"
    dbname: synapse
    host: postgres
    cp_min: 2
    cp_max: 5
registration_shared_secret: "$(rnd)"
macaroon_secret_key: "$(rnd)"
form_secret: "$(rnd)"
EOF

echo "Wrote .env and data/synapse/secrets.yaml (mode 600)."
