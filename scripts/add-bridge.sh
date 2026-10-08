#!/usr/bin/env bash
# Sets up a mautrix bridge whose files are in bridges/<service>/ (compose.yaml + config.yq).
#   scripts/add-bridge.sh <service>
# Steps (each is skipped if already done, so the script can be re-run safely):
#   1. let the bridge generate its default config      -> data/bridges/<service>/config.yaml
#   2. create its Postgres database                     (db name: mautrix_<service>, '-' -> '_')
#   3. apply bridges/<service>/config.yq to the config  (secrets via env: DB_URI, DP_TOKEN)
#   4. let the bridge generate its appservice registration
#   5. register it (and the shared double-puppet appservice) in synapse/homeserver.yaml
# Before running: add "- bridges/<service>/compose.yaml" to the include: list in compose.yaml.
# Afterwards: restart Synapse and start the bridge (the script prints the commands).
set -euo pipefail
cd "$(dirname "$0")/.."
export DOCKER_HOST="${DOCKER_HOST:-unix:///run/user/$(id -u)/docker.sock}"
svc="${1:?usage: add-bridge.sh <service>}"
src="bridges/$svc"; data="data/bridges/$svc"
db="mautrix_${svc//-/_}"
[[ -f "$src/compose.yaml" && -f "$src/config.yq" ]] || { echo "missing $src/compose.yaml or config.yq" >&2; exit 1; }

grep -q "^  - $src/compose.yaml" compose.yaml || {
  echo "Add '  - $src/compose.yaml' under include: in compose.yaml first." >&2; exit 1; }
dc() { docker compose "$@"; }
yq() { dc run --rm --no-deps -T -v "$PWD/$src:/cfg:ro" -v "$PWD/synapse:/synapse" \
         -v "$PWD/data/bridges:/bridges" -e DB_URI -e DP_TOKEN --entrypoint yq "$svc" "$@" </dev/null; }

umask 077
mkdir -p "$data"

# Shared double-puppet appservice (lets bridges show messages you send from your phone as you).
dp=data/bridges/doublepuppet.yaml
if [[ ! -f "$dp" ]]; then
  r() { python3 -c 'import secrets; print(secrets.token_hex(32))'; }
  cat > "$dp" <<EOF
# Shared by all bridges for double puppeting. No url: Synapse never sends events to it.
id: doublepuppet
url:
as_token: $(r)
hs_token: $(r)
sender_localpart: $(r)
rate_limited: false
namespaces:
  users:
    - regex: '@.*:hub\.home\.arpa'
      exclusive: false
EOF
  echo "created $dp"
fi
DP_TOKEN="$(grep '^as_token:' "$dp" | awk '{print $2}')"; export DP_TOKEN

if [[ ! -f "$data/config.yaml" ]]; then
  echo "[1] generating default config"
  dc run --rm --no-deps -T "$svc" </dev/null | tail -2
  # keep a pristine copy for reference/diffing after upgrades
  cp "$data/config.yaml" "$data/config.example.yaml"
fi

if [[ -z "$(docker compose exec -T postgres psql -U postgres -Atc "select 1 from pg_database where datname='$db'" </dev/null)" ]]; then
  echo "[2] creating database $db"
  DB_URI="$(scripts/new-db.sh "$db")"; export DB_URI
else
  echo "[2] database $db exists; reusing URI from config"
  DB_URI="$(yq '.database.uri // .appservice.database.uri' /bridges/"$svc"/config.yaml)"; export DB_URI
fi

echo "[3] applying $src/config.yq"
yq -i --from-file /cfg/config.yq /bridges/"$svc"/config.yaml

# mautrix bots default to a picture hosted on maunium.net, which this hub can't fetch (federation
# is off), so Element keeps retrying it. Copy it locally: bridges/icons/<service>.png (kept in git),
# uploaded through the double-puppet appservice as @piadmin.
avatar="$(yq '.appservice.bot.avatar' /bridges/"$svc"/config.yaml)"
if [[ "$avatar" == mxc://maunium.net/* ]]; then
  echo "[3b] replacing the maunium.net bot picture with a local copy"
  icon="bridges/icons/$svc.png"; mkdir -p bridges/icons data/bridges/icons
  [[ -s "$icon" ]] || curl -sfL -o "$icon" \
    "https://matrix-client.matrix.org/_matrix/media/v3/download/maunium.net/${avatar#mxc://maunium.net/}" || true
  if [[ -s "$icon" ]]; then
    cp "$icon" "data/bridges/icons/$svc.png"
    mxc="$(docker compose exec -T synapse curl -s -X POST -H "Authorization: Bearer $DP_TOKEN" \
      -H 'Content-Type: image/png' --data-binary "@/bridges/icons/$svc.png" \
      "http://localhost:8008/_matrix/media/v3/upload?filename=$svc.png&user_id=%40piadmin%3Ahub.home.arpa" </dev/null |
      python3 -c 'import sys,json; print(json.load(sys.stdin).get("content_uri",""))' 2>/dev/null || true)"
  fi
  if [[ "${mxc:-}" == mxc://hub.home.arpa/* ]]; then
    yq -i ".appservice.bot.avatar = \"$mxc\"" /bridges/"$svc"/config.yaml
    echo "     done. To keep it on re-runs, add this line to $src/config.yq:"
    echo "     .appservice.bot.avatar = \"$mxc\" |"
  else
    echo "     could not upload it (Synapse not up yet?). Re-run this script later." >&2
  fi
fi

if [[ ! -f "$data/registration.yaml" ]]; then
  echo "[4] generating registration"
  dc run --rm --no-deps -T "$svc" </dev/null | tail -2
fi

echo "[5] registering with Synapse"
yq -i '.app_service_config_files = ((.app_service_config_files // []) + ["/bridges/doublepuppet.yaml", "/bridges/'"$svc"'/registration.yaml"] | unique)' /synapse/homeserver.yaml
yq '.app_service_config_files' /synapse/homeserver.yaml

cat <<EOF

Done. Next:
  docker compose up -d --force-recreate synapse   # Synapse reads registrations only at startup
  docker compose up -d $svc
EOF
