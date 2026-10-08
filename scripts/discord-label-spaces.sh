#!/usr/bin/env bash
# mautrix-discord always names its spaces "Discord" and "Direct Messages" and gives them the
# default bot picture (hosted on maunium.net, unreachable with federation off). With one instance
# per account that's ambiguous, so this sets, ONLY where the bridge default is still in place:
#   "Discord"          -> "<Label> - Discord"
#   "Direct Messages"  -> "<Label> - Discord DMs"
#   maunium.net avatar -> the local Discord icon (bridges/icons/discord.png, already uploaded)
# Names/pictures you changed yourself are left alone. Run after logging in; safe to re-run.
#   scripts/discord-label-spaces.sh <label>
set -euo pipefail
cd "$(dirname "$0")/.."
export DOCKER_HOST="${DOCKER_HOST:-unix:///run/user/$(id -u)/docker.sock}"
label="${1:?usage: discord-label-spaces.sh <label>}"
Label="${label^}"
db="mautrix_discord_$label"; reg="data/bridges/discord-$label/registration.yaml"
bot="@discordbot_$label:hub.home.arpa"
AS="$(grep '^as_token:' "$reg" | awk '{print $2}')"
ICON="$(grep -o 'mxc://[^"]*' "bridges/discord-$label/config.yq" | head -1)"

rows="$(docker compose exec -T postgres psql -U postgres -d "$db" -At -F ' ' \
        -c 'select space_room, dm_space_room from "user" where dcid is not null' </dev/null)"
[[ -n "$rows" ]] || { echo "no logged-in user yet for $label" >&2; exit 1; }
read -r space dmspace <<<"$rows"

api() { # method path [json]
  docker compose exec -T synapse curl -s -X "$1" -H "Authorization: Bearer $AS" \
    -H 'Content-Type: application/json' ${3:+-d "$3"} \
    "http://localhost:8008/_matrix/client/v3/rooms/$2?user_id=$bot" </dev/null
}
field() { python3 -c "import sys,json; print(json.load(sys.stdin).get('$1',''))" 2>/dev/null || true; }

fix() { # room default_name new_name
  [[ -n "$1" ]] || return 0
  name="$(api GET "$1/state/m.room.name/" | field name)"
  if [[ "$name" == "$2" ]]; then
    api PUT "$1/state/m.room.name/" "{\"name\": \"$3\"}" >/dev/null && echo "renamed '$2' -> '$3'"
  else
    echo "kept name '$name'"
  fi
  url="$(api GET "$1/state/m.room.avatar/" | field url)"
  if [[ -z "$url" || "$url" == mxc://maunium.net/* ]]; then
    api PUT "$1/state/m.room.avatar/" "{\"url\": \"$ICON\"}" >/dev/null && echo "  set local icon on '$3'"
  else
    echo "  kept picture on '$3'"
  fi
}
fix "$space"   "Discord"         "$Label - Discord"
fix "$dmspace" "Direct Messages" "$Label - Discord DMs"
