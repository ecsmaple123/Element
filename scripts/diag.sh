#!/usr/bin/env bash
# Read-only diagnostics for Element lag / media not updating.
exec </dev/null
cd /home/claude/projects/matrix-hub; export DOCKER_HOST=unix:///run/user/1001/docker.sock
SINCE="${1:-30m}"
echo "== load/mem/io"; uptime; free -m | sed -n 2,3p; vmstat 2 3 | tail -2
echo "== top CPU processes"; ps -eo pcpu,rss,comm --sort=-pcpu | head -8
echo "== temp / throttling"; cat /sys/class/thermal/thermal_zone0/temp; vcgencmd get_throttled 2>/dev/null || echo "(vcgencmd n/a)"
L=$(docker compose logs --since "$SINCE" --no-log-prefix synapse 2>&1)
P=$(echo "$L" | grep "Processed request")
echo "== synapse requests ($SINCE): count by status"
echo "$P" | grep -oE 'B [0-9]{3} "' | sort | uniq -c
echo "== slowest non-sync requests (sec status method path)"
echo "$P" | sed -E 's/.*Processed request: ([0-9.]+)sec.* ([0-9]+)B ([0-9]{3}) "([A-Z]+) ([^ ?"]+).*/\1 \3 \4 \5/' | grep -v '/sync$' | sort -rn | head -12
echo "== /sync summary"
echo "$P" | grep '/sync' | sed -E 's/.*Processed request: ([0-9.]+)sec.* ([0-9]{3}) "GET.*/\1 \2/' |
  awk '{n++; if($1<1)f++; else if($1>=29)p++; else m++; if($2!="200")e++} END {print n" syncs: "f+0" <1s, "m+0" 1-29s, "p+0" long-poll >=29s, non-200: "e+0}'
echo "== media requests by status/type"
echo "$P" | grep -E '/media/' | sed -E 's/.* ([0-9]{3}) "GET [^ ]*\/media\/(thumbnail|download|config|preview_url).*/\1 \2/' | sort | uniq -c
echo "== synapse warnings/errors ($SINCE)"
echo "$L" | grep -E " - (WARNING|ERROR) - " | sed -E 's/^[0-9-]+ [0-9:,]+ - //; s/![A-Za-z0-9]+:hub\.home\.arpa/!ROOM/g; s/\$[A-Za-z0-9_-]{20,}/$EVENT/g; s/@[a-z0-9_.=-]+:hub\.home\.arpa/@USER/g' | cut -c1-150 | sort | uniq -c | sort -rn | head -12
echo "== caddy warnings/errors ($SINCE)"
docker compose logs --since "$SINCE" --no-log-prefix caddy 2>&1 | grep -iE '"level":"(error|warn)"' | sed -E 's/.*"msg":"([^"]*)".*"(uri|error)":"([^"]{0,80}).*/\1 | \3/' | sort | uniq -c | sort -rn | head -8
echo "== bridge errors ($SINCE)"
for b in whatsapp discord-alpha; do echo "  $b: $(docker compose logs --since "$SINCE" $b 2>&1 | grep -cE ' (ERR|FTL) ') ERR, $(docker compose logs --since "$SINCE" $b 2>&1 | grep -cE ' WRN ') WRN"; done
echo "== media store size"; du -sh data/synapse/media_store 2>/dev/null
