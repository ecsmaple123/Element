#!/usr/bin/env bash
# mautrix-discord always names its spaces "Discord" and "Direct Messages". With one instance per
# account that's ambiguous, so this renames them to "Discord · <label>" / "Direct Messages · <label>".
# Run after logging in (the spaces are created at login). Safe to re-run.
#   scripts/discord-label-spaces.sh <label>
set -euo pipefail
cd "$(dirname "$0")/.."
export DOCKER_HOST="${DOCKER_HOST:-unix:///run/user/$(id -u)/docker.sock}"
label="${1:?usage: discord-label-spaces.sh <label>}"
db="mautrix_discord_$label"; reg="data/bridges/discord-$label/registration.yaml"
bot="@discordbot_$label:hub.home.arpa"
AS="$(grep '^as_token:' "$reg" | awk '{print $2}')"

rows="$(docker compose exec -T postgres psql -U postgres -d "$db" -At -F ' ' \
        -c 'select space_room, dm_space_room from "user" where dcid is not null' </dev/null)"
[[ -n "$rows" ]] || { echo "no logged-in user yet for $label" >&2; exit 1; }
read -r space dmspace <<<"$rows"

setname() { # room name
  [[ -n "$1" ]] || return 0
  docker compose exec -T synapse curl -sf -X PUT \
    -H "Authorization: Bearer $AS" -H 'Content-Type: application/json' \
    -d "{\"name\": \"$2\"}" \
    "http://localhost:8008/_matrix/client/v3/rooms/$1/state/m.room.name/?user_id=$bot" </dev/null >/dev/null
  echo "renamed $1 -> $2"
}
setname "$space" "Discord · $label"
setname "$dmspace" "Direct Messages · $label"
