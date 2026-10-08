# matrix-hub — project notes

Self-hosted Matrix hub (Synapse + Element + mautrix bridges) on the home Pi.
Work dir on Pi: `/home/claude/projects/matrix-hub` (local mirror: `C:\pi-work\matrix-hub`).

## Status
- 2026-10-07 — Stage 0 (audit) done. Nothing installed, nothing running, no ports opened.
- 2026-10-07 — Stage 1 plan written (PLAN.md), **awaiting approval** + checks C3/A2.
  The user authorised deleting/restarting the old `/home/pi/matrix` experiment.

- 2026-10-07 — Plan approved. Server name **hub.home.arpa** (permanent). Discord labels: beta, alpha
  (alpha = low-risk test account, bridged first). More Discord accounts may be added later.
  Space naming style chosen by the user: "Alpha - Discord" (scripts follow it).
  `/srv/homeserver` is ignored. The user deleted the old `/home/pi/matrix` experiment and installed `uidmap`.
- 2026-10-07 — **Stage 2 (core) running.** Admin user `@piadmin:hub.home.arpa` created by the user.
- 2026-10-07 — Off-Pi backup copy: user chose to keep it **manual** (pull-backups.sh on the PC).
- 2026-10-07 — **Stage 3 done:** backup script + daily timer, restore script, side-by-side
  restore test passed, first backups copied to the PC.
- 2026-10-07 — **Stage 4 (WhatsApp) done.** The user linked the phone and confirmed send + receive work.
  Bridge health: 1 login, 42 chats, 394 backfilled messages, 2 harmless ERRs (link-preview
  thumbnails 403). Second restore test (database-only, real data) passed.

- 2026-10-08 — **Stage 5 (Discord):** alpha and beta bridged, one mautrix-discord instance each.
  Separation verified (see below). beta's Element→Discord direction not yet exercised live
  (all 37 beta messages carry the right account); re-run `scripts/check-discord-separation.sh` later.
- 2026-10-08 — **Stage 7 (modularity) done:** "Adding a bridge" guide, `remove-bridge.sh`, add-bridge.sh
  now localizes maunium.net bot pictures; full add→remove round trip tested with Signal.
- 2026-10-08 — **Stage 6 (WeChat) researched:** no viable bridge; recommendation: don't bridge. Nothing installed.

## Adding a bridge (Stage 7, tested end to end 2026-10-08)
**Test:** a throwaway Signal bridge was added with exactly these steps, verified, then removed with
`remove-bridge.sh --purge`. Afterwards `compose.yaml` and the Synapse registration list were identical
to before, and the container/DB/role/data were gone. The other bridges were unaffected (pings OK).
All commands run in `~/projects/matrix-hub` as claude.

### A. Ready-made
- **Signal:** `bridges/signal/` exists (v0.2609.0, local bot icon). Start at step 4.
- **Another Discord account:** `scripts/new-discord.sh <label>` does steps 2–6.
  Then do 7–9, log in, run `scripts/discord-label-spaces.sh <label>` and
  `bash scripts/check-discord-separation.sh`.

### B. Any other mautrix bridge (Telegram, Google Messages, Meta, Slack, …)
0. **Check first:**
   - The image has **arm64**: open `https://dock.mau.dev/mautrix/<name>/container_registry`, or
     run the manifest check in Stage 0 notes.
   - Pick the newest release tag (GitHub releases). Read what login needs (e.g. Telegram needs an
     api_id/api_hash from my.telegram.org).
   - Run `./hub.sh backup` and `git commit`.
1. **Find out the bridge's config layout:**
   - **Newer framework (bridgev2):** WhatsApp/Signal style; DB under `.database`, double puppet
     under `.double_puppet.secrets`.
   - **Older framework:** like Discord v0.7; DB under `.appservice.database`, double puppet under
     `.bridge.login_shared_secret_map`.
   - Check the repo's `example-config.yaml` (bridgev2: `pkg/connector/example-config.yaml` +
     mautrix-go `bridgev2/matrix/mxmain/example-config.yaml`) and its default port.
2. **`bridges/<svc>/compose.yaml`:** copy `bridges/signal/compose.yaml`; change the service name,
   image + tag, and `../../data/bridges/<svc>`. **Keep** the `platform` and `security_opt`
   lines (arm64 + seccomp profile). **No** `ports:`.
3. **`bridges/<svc>/config.yq`:** copy from Signal (bridgev2) or the Discord template (older
   framework). Change:
   - the address/port, `appservice.id`, `bot.username`/`displayname`
   - `username_template`, which must be a unique prefix: check with
     `grep -h regex data/bridges/*/registration.yaml`
   - Drop the `bot.avatar` line (step 5 creates it).
4. **Add the include line:** `echo "  - bridges/<svc>/compose.yaml" >> compose.yaml`, then
   `docker compose config --quiet`.
5. **Pull and configure:** `docker compose pull <svc>`, then `scripts/add-bridge.sh <svc>`.
   - It creates the default config, the DB `mautrix_<svc>`, applies config.yq, localizes the bot
     picture, creates the registration and registers it.
   - Copy the printed `.appservice.bot.avatar = …` line into config.yq.
6. **Restart Synapse, start the bridge:**
   `docker compose up -d --force-recreate synapse`, then `docker compose up -d <svc>`.
   Synapse is briefly down (~25 s); other bridges reconnect by themselves.
7. **Verify:**
   - `docker compose logs <svc> | tail` shows "Bridge started".
   - The ping returns `{"duration_ms":…}`:
     `AS=$(grep ^as_token: data/bridges/<svc>/registration.yaml | awk '{print $2}');
     docker compose exec -T synapse curl -s -X POST -H "Authorization: Bearer $AS"
     -H 'Content-Type: application/json' -d '{}'
     http://localhost:8008/_matrix/client/v1/appservice/<appservice.id>/ping`
8. **Log in:** DM `@<bot.username>:hub.home.arpa`, then `login` (`help` lists the options).
   Afterwards, if the bridge's space shows a blank picture, set a PNG/JPEG one yourself (never AVIF).
9. **Wrap up:**
   - Run `./hub.sh backup` (new DBs are included automatically) and `git add -A && git commit`.
   - Add a short section to these notes.
   - Check RAM (`bash scripts/diag.sh 10m`).

### C. A non-mautrix bridge (e.g. heisenbridge for IRC, matrix-appservice-*)
Same pattern, done by hand:
- **Compose file:** `bridges/<name>/compose.yaml` with the same `platform`/`security_opt`/`networks`
  lines and an arm64 image (check!).
- **Database (if needed):** `scripts/new-db.sh <dbname>` prints the URI.
- **Registration:** generate it per that project's docs into `data/bridges/<name>/registration.yaml`
  (url `http://<service>:<port>`, unique namespace).
- **Register and start:** add `/bridges/<name>/registration.yaml` to `app_service_config_files` in
  `synapse/homeserver.yaml`, add the include line, restart Synapse, start the service.
- **Never publish a port. Pin the image tag.**

### D. Removing a bridge
1. In the bot DM: `logout` (invalidates the remote session).
2. `./hub.sh backup`.
3. `scripts/remove-bridge.sh <svc>` (disable; keeps DB + data), or `... --purge` (also drops the DB
   and role and deletes `data/bridges/<svc>/`; asks you to type `PURGE <svc>`).
4. `git add -A && git commit`. Old rooms stay in Matrix; leave them in Element.

## WhatsApp bridge (Stage 4)
- **Bridge:** mautrix-whatsapp `v0.2609.0` (bridgev2, internally "v26.09"); service `whatsapp`,
  internal port 29318 (not published). Bot: `@whatsappbot:hub.home.arpa`; ghosts `@whatsapp_<id>`.
- **Files:**
  - tracked: `bridges/whatsapp/compose.yaml` + `config.yq` (our settings, no secrets)
  - generated: `data/bridges/whatsapp/config.yaml` (full config incl. tokens/DB password),
    `config.example.yaml` (pristine default, for diffing on upgrades), `registration.yaml`
- **Database:** `mautrix_whatsapp` (own role).
- **Double puppeting:** shared appservice `data/bridges/doublepuppet.yaml` (no URL; token lets
  bridges act as *your* Matrix user, so messages you send from the phone appear as you).
  It's a powerful token and lives only in data/ and the backups.
- **Settings:** encryption off (bridge and hub are on the same Pi); backfill 50 msgs per new chat,
  500 catch-up; no full 1-year history request; one "WhatsApp" space per login; logs to stdout only.
- **Health:** Synapse → bridge appservice ping OK (4 ms). RAM ≈45 MB after the first sync
  (Synapse grew to ≈315 MB with 44 rooms). Backups grew to ≈54 MB (WhatsApp media).
- **Logs:** "Event handling is taking long" warnings during the first history sync are expected on the SD card.
- **Link the phone:** DM `@whatsappbot:hub.home.arpa` → `login qr` (or `login phone` for a pairing
  code). On the phone: WhatsApp → Settings → Linked devices → Link a device.
- **Keep the link alive:** the phone must come online at least every ~14 days, or WhatsApp drops
  the linked device.
- **Upgrade:** bump the tag in `bridges/whatsapp/compose.yaml` → `./hub.sh backup` →
  `docker compose up -d whatsapp`. It migrates its DB itself. Read the release notes first.
- **Stop just this bridge:** `docker compose stop whatsapp`. **Remove it:** see "Adding a bridge" → D
  (`logout` in the bot DM, then `scripts/remove-bridge.sh whatsapp [--purge]`).

## Discord bridges (Stage 5)
- **Model:** one mautrix-discord `v0.7.7` instance per Discord account (that version supports only
  one Discord login per Matrix user, and separate instances keep identities and rooms apart).
- **Per account `<label>`:**
  - service `discord-<label>`, internal port 29334
  - DB `mautrix_discord_<label>`
  - bot `@discordbot_<label>`, ghosts `@discord_<label>_*`
  - rooms "[<label>] #channel", people "Name [<label>]", command prefix `!dc-<label>`
  - only `@piadmin` may use it
- **Accounts:**
  - `alpha` (low-risk test, since 2026-10-07): spaces "Alpha - Discord", "Alpha - Discord DMs"
  - `beta` (since 2026-10-08): spaces "Beta - Discord" (named by user), "Beta - Discord DMs"
- **Add an account:**
  1. `scripts/new-discord.sh <label>`
  2. `docker compose up -d --force-recreate synapse`
  3. `docker compose up -d discord-<label>`
  4. Log in via the bot DM, then `scripts/discord-label-spaces.sh <label>`
  5. `bash scripts/check-discord-separation.sh`
- **Settings (template `bridges/discord-template/`):**
  - backfill: DMs 20 initial / 50 missed, channels 0 initial / 20 missed
  - channels muted on creation, no federation, encryption off, local bot icon
- **Separation check (`scripts/check-discord-separation.sh`, read-only), 2026-10-08:**
  - different Discord accounts per instance
  - no room with users from two instances
  - every named portal carries its own label
  - each space holds rooms of one instance only
  - every message attributed to @piadmin left from that instance's own account
    (alpha 44/0, beta 37/0)
- **Health check on alpha (2026-10-08, ~1 day in):** login active; no captcha/401/403/429/invalid session.
  Warnings are only "unknown event type" (voice/boost events the bridge ignores).
- **Not bridged** (checked against the v0.7.7 source):
  - voice channels (incl. their text chat), stage channels, forum channels
  - voice/video calls (DM calls show only "started a call")
  - Use the Discord app for voice; running it alongside the bridge is fine.
  - WhatsApp calls aren't bridged either (only a notice).
- **Blocked/ignored Discord users** (checked against the v0.7.7 source): the bridge doesn't check
  Discord's block/ignore lists, so their **channel messages are bridged and shown in full** (Discord's
  servers deliver them to every client; only the Discord app collapses them). Blocked users can't DM
  you on Discord anyway.
  - **Remedy:** ignore the person in Element (click name → Ignore). Synapse then filters them out
    server-side.
  - **Per instance:** ghosts are per instance, so "Name [alpha]" and "Name [beta]" are separate
    users to ignore.
  - **No sync:** Matrix ignore and Discord block don't sync in either direction.
- **Risk:** this is a self-bot login (against Discord ToS). Watch for captchas, forced re-logins or
  phone-verification prompts; if one appears, stop that instance
  (`docker compose stop discord-<label>`) before trying again.
- **Upgrade:** bump the tag in the template **and** each `bridges/discord-*/compose.yaml`, back up,
  then `docker compose up -d`. The multi-login rewrite (`megadiscord` branch) is unreleased as of
  2026-10-08; switching to it later would be a migration (new rooms).

## WeChat (Stage 6, researched 2026-10-08): not viable, nothing installed
| Option | How it connects | Status (checked 2026-10-08) | Runs on this Pi? |
|---|---|---|---|
| duo/matrix-wechat + matrix-wechat-agent | Hooks the **Windows** WeChat 3.7.0.30 client (ComWeChatRobot, archived 2023) | Last real commit 2024-02. Open issues: client "version too low" (2024-04), new Synapse incompatible (2024-09/11), "Unable to log in" (2025-12) | No (needs an x86 Windows PC/VM running 24/7) |
| palpo-im/matrix-bridge-wechat (Rust) | Same Windows agent as above | 1 release (2026-02), 0 stars, built for the Palpo homeserver | No |
| wechaty/matrix-appservice | Wechaty puppets (web protocol blocked for most accounts; paid PadLocal) | Last push 2022-09 | Unmaintained |
| LeiShi1313/mautrix-wechat (wechat-box) | Windows WeChat in Wine (x86) | Last push 2022-08 | No |
| Gewechat / paid "iPad protocol" APIs (GeWeAPI etc.) | Emulated iPad client on someone else's server | Gewechat **discontinued**, citing a crackdown on illegal WeChat data collection. Paid APIs hold your session on third-party servers | Technically, but a privacy + ban risk |
| Official "ClawBot" / iLink bot API (Tencent, 2026-03) | Official HTTP API | Real and official, but only a conversation between you and **one bot contact**; it can't read or send in your existing chats or groups. Staged rollout (iOS first) | Not a bridge |

- **Risks of the unofficial routes:** WeChat's own help pages say unauthorized plug-ins/clients can
  lead to **permanent account blocking** and block unblock requests. Tencent tightened enforcement
  against automation in 2026.
- **Decision (recommended):** don't bridge WeChat. Keep it on the phone / official desktop client.
- **Revisit if:** a maintained bridge appears that uses an official chat-access API (not the ClawBot
  bot-only API), or Tencent opens personal-chat access. Watch: mautrix bridge list, matrix.org/ecosystem/bridges.

## Discord: choosing which channels are bridged (any instance; example: alpha)
In the bot DM (`@discordbot_<label>`), per server:
1. `guilds bridge <server ID>`
2. `guilds bridging-mode <server ID> if-portal-exists`: only channels that already have a room
   are forwarded; others are ignored and no new rooms get created.
3. `create-portal <channel ID>` for each wanted channel (Discord Developer Mode → right-click → Copy ID).
- Drop a channel: in its room, `!dc-<label> delete-portal` (it stays gone in `if-portal-exists` mode;
  in the default `create-on-message` mode it would come back with the next message).
- Modes: `nothing` | `if-portal-exists` | `create-on-message` (default) | `everything` (= `--entire`).
- Muting/leaving a room in Element does NOT stop forwarding. Ignored channels add no API traffic.

## Future idea: message watcher / highlights (proposed 2026-10-08, not built)
**Goal:** read every incoming message across all bridges and notify only on messages of interest the
user defines.

**Level 1 (available now, nothing to install)**
- Element → Settings → Notifications → keywords. Synapse evaluates them server-side.
- Set noisy rooms to **"Mentions & keywords"**, not **Mute**: Mute also silences keywords.
- Plain word/glob matching only.

**Level 2: watcher service (a future stage; same pattern as a bridge)**
- One small container (Python, ~30–50 MB), no ports. Logs in as its own device on @piadmin and is
  **read-only by design**: it never posts in bridged rooms.
- Rules file (YAML): regex on text; sender; room/network (WhatsApp, `[alpha]`, `[beta]`…);
  time windows; AND/OR combinations.
- Matches are posted to one private **"Highlights"** room (sender, room, text, link to the original),
  so it's one notification channel.
- **Optional LLM step**, opt-in per room, only for messages that passed a cheap pre-filter:
  natural-language criteria or a daily digest. This sends message text to an external API
  (privacy + cost); a useful local model is not realistic on a Pi 4.
- **Security:** its access token can read everything; it lives in `data/` and the backups.
- **Design rule:** it must ignore bridge ghosts/bots (no echo loops).

**Considered: Hermes Agent (Nous Research)**, checked 2026-10-08 against its docs.
- **What it is:** a conversational agent framework with a Matrix gateway.
  - Answers DMs, and @mentions in rooms by default (`MATRIX_REQUIRE_MENTION`).
  - Has cron jobs, memory and an allowlist (`MATRIX_ALLOWED_USERS`).
- **Requirements:** Linux x86_64/aarch64 (arm64 Docker image, so it would need our seccomp profile)
  and an external LLM API (Nous Portal / OpenRouter / OpenAI-compatible).
- **Fit:** it's built to be an assistant you talk to, not a silent filter.
  - To "see everything" it would have to run as @piadmin or be in every bridged room.
  - Anything it posts in a bridged room would go out to real WhatsApp/Discord contacts (as you,
    if it runs as your user).
  - Its docs also warn about echo loops with bridge ghosts.
- **Conclusion:** not suitable as the watcher. It could later be an *on-demand assistant* layered on
  top: a dedicated bot user, only in its own private room, `MATRIX_ALLOWED_USERS=@piadmin`,
  `MATRIX_IGNORE_USER_PATTERNS` for all ghosts, never invited to bridged rooms, fed by the watcher's
  Highlights/digest rather than raw rooms.

## Troubleshooting
- **Diagnostics:** `bash scripts/diag.sh [30m]` (read-only). It shows load, Synapse request
  statuses, the slowest requests, a /sync summary, media failures, warnings and bridge error counts.
- **Missing pictures, 2026-10-08:**
  1. *Bridge defaults on maunium.net.* Bridge bots default to pictures hosted on maunium.net;
     federation is off, so Synapse can't fetch them (403) and Element retries constantly.
     - Fix: the icons were copied to `bridges/icons/` and uploaded locally
       (WhatsApp `mxc://hub.home.arpa/ymqSNwrSCjRjfHXpixyiWCll`, Discord
       `mxc://hub.home.arpa/vhUOzyIPsahjXUQYovunUfaH`), then set via `.appservice.bot.avatar`
       in the yq files. New Discord instances get it from the template.
     - Still on maunium.net: "bridge info" state in ~45 rooms (WhatsApp's network icon is
       hard-coded). It's only shown in room settings → Bridges, so it's harmless.
  2. *AVIF uploads.* Synapse can't thumbnail **AVIF** images ("Failed to find any generated
     thumbnails" → 400), and Element always asks for a thumbnail. Use PNG/JPEG/WebP for
     avatars and space pictures.
- **"Lag" check, 2026-10-08:** server-side sync was healthy (545 syncs/3h, ≤0.06 s CPU each,
  3 aborted by the browser). If Element feels slow, check client-side first: the certificate
  must be trusted (service worker), avoid hard reloads (Ctrl+F5 bypasses the service worker),
  and try another browser.
- **Discord spaces:** `scripts/discord-label-spaces.sh <label>` (after login) renames the
  default "Discord"/"Direct Messages" spaces to "<Label> - Discord"/"<Label> - Discord DMs"
  and sets the local icon. It only replaces bridge defaults, never names/pictures you chose.

## Open items
- Future idea: message watcher / highlights + Hermes assessment (section above). Not started.
- Off-Pi backup copy is manual by choice (2026-10-07); reminder: run pull-backups.sh regularly.
- Optional: encrypt off-Pi backups (gpg/age) if the PC copy might end up in a cloud-synced folder.
- Optional: test a restore on an amd64 machine with Docker, if one becomes available.

## Core services (Stage 2)
| Service | Image | Notes |
|---|---|---|
| postgres | postgres:17.11-alpine | volume `matrixhub_pgdata` (in .docker-data) |
| synapse | matrixdotorg/synapse:v1.162.0 | config `synapse/`, data + secrets `data/synapse/` |
| element | vectorim/element-web:v1.12.30 | config `element/config.json` |
| caddy | caddy:2.11.7-alpine | **192.168.0.129:8443/tcp**, local CA in `data/caddy/caddy/pki/` |

- URL: https://192.168.0.129:8443 (Element; Synapse is at /_matrix behind it).
- Root CA for devices: `data/caddy/caddy/pki/authorities/local/root.crt`
  (copy on the PC: `C:\pi-work\matrix-hub\matrix-hub-root-ca.crt`, valid until 2036).
  Its private key sits next to it: anyone holding it can impersonate any HTTPS site to devices
  that trust it. It's included in backups, so keep backups private.
- Measured RAM (idle): ≈570 MB in total across rootless Docker and all 4 services. `docker stats` shows 0 B
  because the memory cgroup is off. Measure with:
  `ps -eo uid=,rss=,comm= | awk '$1==1001 || ($1>=165536 && $1<=231071) {s+=$2} END {print s/1024 " MB"}'`
- Verified 2026-10-07: TLS OK; client API 200; registration 403; federation and key endpoints 404;
  the only new host listener is 192.168.0.129:8443/tcp (no UDP); reachable from the LAN PC.

### Rootless Docker (claude)
- Installed by `dockerd-rootless-setuptool.sh install` → `~/.config/systemd/user/docker.service`,
  plus `~/.config/systemd/user/docker.service.d/10-priority.conf` (Nice=10, IO best-effort 7).
- `~/.config/docker/daemon.json`: data-root = `matrix-hub/.docker-data`, log driver `local` 5m×3.
- Linger enabled (`loginctl enable-linger claude`), so it starts at boot without a login.
- CLI context `rootless` is the default for claude. hub.sh also sets DOCKER_HOST explicitly.
- Socket: `/run/user/1001/docker.sock`. Network: rootlesskit 2.3.4 + slirp4netns, builtin port driver.

### Stop / start / remove
- Stop containers (data kept): `cd ~/projects/matrix-hub && ./hub.sh stop` (start: `./hub.sh up`)
- Stop everything incl. claude's Docker daemon: `./hub.sh daemon-stop`. Until the next boot or
  `./hub.sh daemon-start`. To also skip it at boot: `systemctl --user disable docker.service`
- **Remove completely (one command):** `./hub.sh remove` (also removes the backup timer; backups/ are kept). It asks for confirmation, then removes the containers,
  the database volume, images and rootless Docker. The system Docker daemon / the VPNs are untouched.
- None of these touch the VPNs: different daemon, no firewall/routing changes.

## Backups (Stage 3, 2026-10-07)
- **What a backup contains:** `./hub.sh backup` (also run daily at ~04:15 by the systemd *user*
  timer `matrixhub-backup.timer`) writes `backups/matrix-hub-<timestamp>/`:
  - `db/globals.sql`: Postgres roles.
  - `db/<db>.dump`: every database, auto-discovered, so bridge DBs are included without changes.
    These are logical dumps, so they work on any CPU type.
  - `files.tar.gz`: the whole project folder (configs, `.env`, git history, `data/` with the
    Synapse signing key + secrets + media, the Caddy CA, bridge state) except `.docker-data/`
    and `backups/`.
  - `MANIFEST`: versions + row counts. `SHA256SUMS`.
- **Retention:** the 7 newest backups stay on the Pi. Each one is ~0.4 MB now and grows with
  media and history.
- **Off-Pi copy:** on the PC run `bash C:\pi-work\matrix-hub\pull-backups.sh` (Git Bash). It copies
  new backups, verifies their checksums, and keeps 14. *Not automated yet; see "Open items".*
- **Sensitive:** backups hold every secret, the CA private key and message history.
  Folders are mode 700/600 on the Pi. Keep the PC copy private.
- **Timer control:** `systemctl --user list-timers` / `systemctl --user disable --now matrixhub-backup.timer`.
  Logs: `journalctl --user -u matrixhub-backup`.

## Restore (tested 2026-10-07)
**Test performed (on the Pi, side by side):**
- **Method:** used only a copied backup folder → extracted `files.tar.gz` into a new folder →
  `scripts/restore.sh` under the separate project `matrixhub-restoretest` (own network
  10.231.1.0/24, own DB volume, 127.0.0.1:18443).
- **Results:**
  - All row counts matched the MANIFEST.
  - The signing key was identical.
  - The restored CA served valid HTTPS.
  - Element loaded.
  - The `@piadmin` row, password hash included, was identical to live.
  - A throwaway admin created via the restored shared secret could log in, create a room and
    send a message.
- **Live hub:** unaffected throughout.
- **Safety check:** restore.sh refused to run against the live project name.
- **Afterwards:** the test copy was deleted.
- **Second test (2026-10-07, after WhatsApp):** database-only (`RESTORE_START=0`), side by side.
  The counts of every Synapse + mautrix_whatsapp table matched live (Synapse events: 1303 vs 1305;
  live kept receiving). The bridge config/session was identical. **No bridge was started in the copy.**
- **Not tested:** restore on a different CPU type (amd64). The DB dumps are architecture-independent,
  but the compose overrides below for amd64 are untested.

### Restore steps on a new machine
1. **Copy the backup** folder `matrix-hub-<timestamp>/` to the machine.
   Check it: `cd <backup> && sha256sum -c SHA256SUMS`.
2. **Get Docker running:**
   - *New 32-bit Pi like this one:* admin installs `docker-ce`, `docker-ce-rootless-extras`,
     `docker-compose-plugin` and `uidmap`, and creates user `claude` with a /etc/subuid range.
     Then, as claude: write `~/.config/docker/daemon.json` (see "Rootless Docker" above),
     `PATH=/usr/sbin:/sbin:$PATH dockerd-rootless-setuptool.sh install`, the priority drop-in,
     and `loginctl enable-linger claude`.
   - *Ordinary amd64/arm64 machine with Docker:* nothing special.
     Then `export DOCKER_HOST=unix:///var/run/docker.sock` (or your socket).
3. **Unpack the files:**
   `mkdir -p ~/projects/matrix-hub && tar -xzf <backup>/files.tar.gz -C ~/projects/matrix-hub`
4. **Only if the machine differs from this Pi,** append to `.env`:
   - `HUB_PLATFORM=linux/amd64` (if amd64)
   - `HUB_SECOPT=no-new-privileges:true` (if the host is NOT a 32-bit Docker install; it keeps that
     host's default seccomp profile)
   - `HUB_BIND=<new LAN IP>`
   - If the IP changed, also replace `192.168.0.129` in `caddy/Caddyfile`, `element/config.json`
     and `synapse/homeserver.yaml` (public_baseurl). The server name stays `hub.home.arpa`.
5. **Stop the old hub for good first** (if it still runs anywhere): two copies of a bridge with the
   same WhatsApp/Discord session must never run at once. Then
   `cd ~/projects/matrix-hub && ./hub.sh restore <backup>`. It refuses if this project already has
   containers. `RESTORE_START=0 ./hub.sh restore <backup>` restores the databases only, without
   starting anything.
6. **Re-enable backups:** copy `scripts/systemd/matrixhub-backup.*` to `~/.config/systemd/user/`
   and `systemctl --user enable --now matrixhub-backup.timer`.
7. **Devices:** they keep trusting the same CA (it's in the backup). Log in again if needed.
   Bridges may need re-linking if the backup is old (Stage 4+ will note specifics).

### VPN check (after any stage that starts something)
As `pi`: `docker ps --filter name=<vpn-container> --format '{{.Names}} {{.Status}}'` and
`<check the VPN handshakes>`. From a phone on mobile data, connect each VPN and load a page.

## Decisions (see PLAN.md for reasoning)
- Federation: off (not needed for bridges). Registration: closed.
- Containers: separate **rootless Docker** as claude; the rootful daemon (runs the VPN) is never used.
- All arm64 images + `seccomp-arm64.json` (Docker 28.5.2 default profile with archMap replaced by
  `architectures: [SCMP_ARCH_ARM, SCMP_ARCH_AARCH64]`). Verified: default → exit 159;
  custom → `aarch64`, `Seccomp: 2` (filter active), and `unshare -U` is still refused.
  Regenerate this file if Docker gets a major update (source: moby vendor/github.com/moby/profiles/seccomp/default.json).
- Synapse containers run as container-root = host user claude (rootless), so data files stay claude-owned.
- Synapse + Postgres; Caddy (internal CA) serves Element + proxies Synapse on 192.168.0.129:8443.
- Discord: one mautrix-discord instance per account.
- Server name: `hub.home.arpa` (chosen 2026-10-07; permanent).

## Findings after Stage 0
- C1: arm64 container produced no output; old Synapse crash-loops with exit 159 (SIGSYS) →
  32-bit Docker's seccomp filter kills 64-bit syscalls (hypothesis).
- Interfaces: eth0 192.168.0.129/24, <vpn-if-1> <vpn-subnet>, <vpn-if-2> <vpn-subnet>, docker0 172.17/16,
  br-matrix 172.18/16.
- Present: dbus-user-session, docker-ce-rootless-extras; max_user_namespaces 29185.
  Missing: uidmap. The user systemd manager only delegates the `pids` controller.
- mautrix-discord v0.7.7 is still the legacy framework (one login per Matrix user);
  `megadiscord` branch = unreleased rewrite. mautrix-whatsapp v0.2609.0 is bridgev2.
- Latest stable (2026-10-07): Synapse v1.162.0, Element Web v1.12.30, Caddy 2.11.7.

## Stage 0 audit (2026-10-07)

### Hardware / OS
- Raspberry Pi 4 Model B Rev 1.5, 4 cores, 7.6 GiB RAM (≈7.1 GiB available), swap only 99 MiB.
- Raspbian 11 (bullseye), kernel 6.1.21-v8+ **aarch64**, userland **32-bit armhf**, Python 3.9.2.
- Storage: one 64 GB SD card (`/` ext4, 45 GB free). No SSD → mind DB write wear; backups matter.
- Idle: load ~0.0, 365 MiB RAM used, 40 °C.

### Image architecture check
| Image | Platforms published |
|---|---|
| matrixdotorg/synapse | amd64, arm64 (no armv7) |
| vectorim/element-web | amd64, arm64 (no armv7) |
| dock.mau.dev/mautrix/whatsapp | amd64, arm64 |
| dock.mau.dev/mautrix/discord | amd64, arm64 (latest release v0.7.7) |
| postgres:16 | includes arm/v7 and arm64/v8 |

→ The stack must run **arm64 containers** (`platform: linux/arm64`) on the 64-bit kernel.
  The armhf Docker daemon defaults to arm/v7, so every service needs an explicit platform.
  Not yet proven on this Pi (claude has no Docker access) — see check C1 in NEEDS_ADMIN.md.

### Docker
- docker-ce 28.5.2 + compose plugin v5.0.2 installed, rootful daemon active.
- `/var/run/docker.sock` is root:docker; docker group = {pi}. `claude` is NOT in it (good, keep it so).
- **the VPN runs in Docker** (`<vpn-dir>/`, not opened). The rootful daemon is
  therefore VPN infrastructure: do not restart it, change daemon.json, or prune anything on it.
- Rootless Docker pieces present: `dockerd-rootless-setuptool.sh`, `rootlesskit`, `slirp4netns` 1.0.1,
  `/etc/subuid` + `/etc/subgid` entries for claude (165536:65536).
  Missing: `newuidmap`/`newgidmap` (package `uidmap`, needs admin).
- Linger for claude: off. polkit allows self-enable (`loginctl enable-linger` without sudo).
- cgroup v2; **memory controller is not enabled** (kernel cmdline lacks `cgroup_enable=memory`)
  → container memory limits cannot be enforced. Delegated to user: cpu, cpuset, io, pids.

### Existing data (do not delete without asking)
- `/home/pi/matrix/` — old experiment from Jul–Sep 2026: compose with `postgres:16` +
  `matrixdotorg/synapse:latest` (`platform: linux/arm64`, port 8008).
  `synapse/` is empty (no homeserver.yaml ever generated); `postgres/` is an initialised data dir (uid 999).
  Not listening on 8008 now. Whether its containers exist is unknown (check C2).
- `/srv/homeserver` — empty dir, owner claude:group homeserver, setgid, created 2026-10-07.
  Group `homeserver` = {claude, pi}.

### Listening ports (avoid all of these)
| Proto | Port | Bound | Likely owner |
|---|---|---|---|
| tcp | 22 | all | sshd |
| tcp | 80 | all | lighttpd (Pi-hole admin config) |
| tcp | 5335, 8953 | localhost | unbound (+ control) |
| tcp | 8581 | all | Homebridge UI |
| tcp | 51761, 54096 | all | probably Homebridge accessory bridges |
| udp | **<vpn-port>**, **<vpn-port>** | all | **VPNs — never touch** |
| udp | 5353 | all | avahi mDNS |
| udp | 5335 | localhost | unbound |
| udp | 36952, 38397 | all | unknown (ephemeral; avahi/homebridge?) |

Process owners can't be shown without root; VPN attribution is inferred from port numbers.

### Other services seen
avahi, bluetooth, containerd, cron, ddclient (dynamic DNS), dhcpcd, docker, homebridge,
lighttpd, ModemManager, ssh, unbound, unattended-upgrades, wpa_supplicant.
