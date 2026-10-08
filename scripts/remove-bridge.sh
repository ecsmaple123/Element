#!/usr/bin/env bash
# Removes one bridge from the hub (the reverse of add-bridge.sh).
#   scripts/remove-bridge.sh <service>            # disable: keeps DB + data, can be re-added
#   scripts/remove-bridge.sh <service> --purge    # also drops its DB/role and deletes its data (asks)
# FIRST log the remote account out in the bot DM (`logout`), so the WhatsApp/Discord/Signal session
# is invalidated on their side too. Take a backup (./hub.sh backup) before --purge.
# Not touched: bridges/<service>/ (tracked files; delete with git if unwanted), the shared
# double-puppet registration, and the Matrix rooms the bridge created (leave them in Element).
set -euo pipefail
cd "$(dirname "$0")/.."
export DOCKER_HOST="${DOCKER_HOST:-unix:///run/user/$(id -u)/docker.sock}"
svc="${1:?usage: remove-bridge.sh <service> [--purge]}"; purge="${2:-}"
src="bridges/$svc"; data="data/bridges/$svc"; db="mautrix_${svc//-/_}"
inc="  - $src/compose.yaml"

if grep -qxF "$inc" compose.yaml; then
  echo "[1] stopping and removing the $svc container"
  docker compose rm -sf "$svc" </dev/null
  echo "[2] removing its Synapse registration"
  # yq comes from the bridge's own image, so do this while the service is still included.
  docker compose run --rm --no-deps -T -v "$PWD/synapse:/synapse" --entrypoint yq "$svc" -i \
    '.app_service_config_files -= ["/bridges/'"$svc"'/registration.yaml"]' /synapse/homeserver.yaml </dev/null
  echo "[3] removing it from compose.yaml include:"
  grep -vxF "$inc" compose.yaml > compose.yaml.tmp && mv compose.yaml.tmp compose.yaml
  docker compose config --quiet
  echo "[4] restarting Synapse (it reads registrations only at startup)"
  docker compose up -d --force-recreate synapse </dev/null
  for _ in $(seq 1 40); do
    [[ "$(docker inspect -f '{{.State.Health.Status}}' "$(docker compose ps -q synapse)")" == healthy ]] && break; sleep 3
  done
  echo "    synapse: $(docker inspect -f '{{.State.Health.Status}}' "$(docker compose ps -q synapse)")"
else
  echo "$svc is not in compose.yaml include: (already disabled)"
fi

if [[ "$purge" == "--purge" ]]; then
  echo "PURGE deletes database $db and $data (session, config, tokens). There's no undo except a backup."
  read -rp "Type PURGE $svc to continue: " ans
  [[ "$ans" == "PURGE $svc" ]] || { echo "Not purged."; exit 0; }
  docker compose exec -T postgres psql -U postgres -v ON_ERROR_STOP=1 -q \
    -c "DROP DATABASE IF EXISTS $db" -c "DROP ROLE IF EXISTS $db" </dev/null
  rm -rf "$data"
  echo "Purged database $db and $data."
fi
echo "Done. Its old rooms stay in Matrix; leave them in Element if you don't want them."
