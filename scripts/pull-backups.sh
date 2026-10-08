#!/usr/bin/env bash
# Run on the PC (Git Bash): copies matrix-hub backups from the Pi that aren't here yet,
# verifies their checksums, and keeps the newest $KEEP locally (default 14).
# The backups contain secrets, keys and message history: keep this folder private.
set -euo pipefail
cd "$(dirname "$0")"
KEEP="${KEEP:-14}"
mkdir -p backups
for b in $(ssh pi 'ls -1 /home/claude/projects/matrix-hub/backups' 2>/dev/null); do
  [[ -d "backups/$b" ]] && continue
  scp -q -r "pi:/home/claude/projects/matrix-hub/backups/$b" "backups/$b.partial" 2>/dev/null
  (cd "backups/$b.partial" && sha256sum --quiet -c SHA256SUMS)
  mv "backups/$b.partial" "backups/$b"
  echo "pulled $b"
done
ls -1d backups/matrix-hub-* | head -n -"$KEEP" | xargs -r rm -rf
echo "Local backups: $(ls -1d backups/matrix-hub-* | wc -l) in $(pwd)/backups"
