#!/usr/bin/env bash
# Verifies that Discord bridge instances are isolated from each other. Read-only.
#   bash scripts/check-discord-separation.sh
exec </dev/null
cd /home/claude/projects/matrix-hub; export DOCKER_HOST=unix:///run/user/1001/docker.sock
labels=$(ls -d data/bridges/discord-* | sed 's#.*/discord-##')
s() { docker compose exec -T postgres psql -U postgres -d synapse -At -F ' | ' -c "$1"; }
echo "== logins per instance (Discord account IDs hashed, not shown)"
for l in $labels; do
  r=$(docker compose exec -T postgres psql -U postgres -d mautrix_discord_$l -At -c 'select md5(dcid) from "user" where dcid is not null and discord_token is not null')
  echo "  $l: ${r:-NOT LOGGED IN}" | cut -c1-30
  eval "h_$l=$r"
done
n=$(for l in $labels; do docker compose exec -T postgres psql -U postgres -d mautrix_discord_$l -At -c 'select md5(dcid) from "user" where dcid is not null'; done | sort | uniq -d | wc -l)
echo "  same Discord account in two instances: $([ "$n" = 0 ] && echo 'NO (good)' || echo 'YES (PROBLEM)')"

echo "== rooms containing users of more than one Discord instance (expect none)"
s "select room_id, string_agg(distinct substring(state_key from '^@discord(?:bot)?_([a-z0-9]+)'), ',')
   from current_state_events where type='m.room.member' and state_key ~ '^@discord(bot)?_[a-z0-9]+[_:]'
     and membership = 'join'
   group by room_id having count(distinct substring(state_key from '^@discord(?:bot)?_([a-z0-9]+)')) > 1" | sed 's/^/  /'
echo "  (end of list)"

echo "== portal rooms per instance, and which spaces they sit in"
for l in $labels; do
  docker compose exec -T postgres psql -U postgres -d mautrix_discord_$l -At -c 'select mxid from portal where mxid is not null' > /tmp/portals_$l
  echo "  $l: $(wc -l < /tmp/portals_$l) portal rooms; names not starting with [$l]: $(
    s "select count(*) from room_stats_state where room_id in ($(sed "s/.*/'&'/" /tmp/portals_$l | paste -sd, -)) and coalesce(name,'') not like '[$l]%' and coalesce(name,'') <> ''" 2>/dev/null)"
done
echo "== spaces and the instances their child rooms belong to (expect one instance per space)"
for l in $labels; do for r in $(cat /tmp/portals_$l); do echo "$r $l"; done; done | sort > /tmp/portal_owner
s "select c.room_id, c.state_key from current_state_events c join event_json j using (event_id)
   where c.type='m.space.child' and j.json::json->'content'->>'via' is not null" | sed 's/ | / /' | sort -k2 > /tmp/space_children
join -1 2 -2 1 -o 1.1,2.2 /tmp/space_children /tmp/portal_owner | sort -u | awk '{print $1}' | uniq -d > /tmp/mixed_spaces
for sp in $(join -1 2 -2 1 -o 1.1,2.2 /tmp/space_children /tmp/portal_owner | sort -u | awk '{print $1}' | sort -u); do
  owners=$(join -1 2 -2 1 -o 1.1,2.2 /tmp/space_children /tmp/portal_owner | awk -v s="$sp" '$1==s {print $2}' | sort -u | paste -sd,)
  name=$(s "select coalesce(name,'?') from room_stats_state where room_id='$sp'")
  echo "  '$name' -> $owners"
done
rm -f /tmp/portals_* /tmp/portal_owner /tmp/space_children /tmp/mixed_spaces
echo "== messages you sent from Matrix: which Discord account did each go out as?"
for l in $labels; do
  docker compose exec -T postgres psql -U postgres -d mautrix_discord_$l -At -F ' ' -c "
    select count(*) filter (where m.dc_sender = u.dcid), count(*) filter (where m.dc_sender <> u.dcid),
           coalesce(to_char(to_timestamp(max(m.timestamp)/1000), 'YYYY-MM-DD HH24:MI'), '-')
    from message m cross join (select dcid from \"user\" where dcid is not null) u
    where m.sender_mxid = '@piadmin:hub.home.arpa'" |
  awk -v l="$l" '{print "  " l ": " $1 " sent as its own account, " $2 " as ANOTHER account" ($2>0?" (PROBLEM)":"") "; latest " $3 " " $4}'
done
