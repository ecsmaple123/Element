#!/usr/bin/env bash
# Adds one mautrix-discord instance for one Discord account.
#   scripts/new-discord.sh <label>        label: lowercase letters/digits, e.g. alpha
# Creates bridges/discord-<label>/ from bridges/discord-template/, adds it to compose.yaml's
# include: list, then runs scripts/add-bridge.sh (config, database, registration).
# Everything the account touches is tagged with the label:
#   bot @discordbot_<label>, ghosts @discord_<label>_*, rooms "[<label>] #channel",
#   names "Name [<label>]", command prefix !dc-<label>.
set -euo pipefail
cd "$(dirname "$0")/.."
label="${1:?usage: new-discord.sh <label>}"
[[ "$label" =~ ^[a-z][a-z0-9]{0,15}$ ]] || { echo "label must be lowercase letters/digits" >&2; exit 1; }
svc="discord-$label"; dir="bridges/$svc"

if [[ ! -d "$dir" ]]; then
  mkdir -p "$dir"
  sed "s/LABEL/$label/g" bridges/discord-template/compose.yaml.tmpl > "$dir/compose.yaml"
  sed "s/LABEL/$label/g" bridges/discord-template/config.yq.tmpl > "$dir/config.yq"
  echo "created $dir"
fi
if ! grep -q "^  - $dir/compose.yaml" compose.yaml; then
  echo "  - $dir/compose.yaml" >> compose.yaml   # include: is the last block in compose.yaml
  echo "added $dir/compose.yaml to include:"
fi
scripts/add-bridge.sh "$svc"
