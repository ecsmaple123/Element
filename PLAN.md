# matrix-hub — Stage 1 plan (2026-10-07, awaiting approval)

## 0. The blocking discovery: 64-bit containers are killed on this Pi

- Synapse, Element Web, mautrix-whatsapp and mautrix-discord only publish **arm64** images.
- Your C1 test pulled an arm64 image but printed nothing, and the old Synapse container
  loops with exit **159 = 128 + SIGSYS(31)**. That's a seccomp kill, not "exec format error",
  so the 64-bit kernel *does* start arm64 programs.
- **Hypothesis:** Docker installed as 32-bit (armhf) builds its default seccomp filter for the
  32-bit ARM syscall table only. Any 64-bit program gets SIGSYS on its first syscall.
- **Fix (no reinstall):** give arm64 containers a copy of Docker's default seccomp profile with
  `SCMP_ARCH_AARCH64` added to its architecture list. That keeps the normal syscall sandbox;
  we do **not** run `seccomp=unconfined`.
- **Confirm first:** check C3 in NEEDS_ADMIN.md (one test with seccomp disabled, as a diagnostic only).
- **If C3 still fails:** the clean fallback is moving the Pi to 64-bit Raspberry Pi OS. That's a
  reinstall which disrupts the VPNs, so it's your call and not part of this plan.

## 1. How containers run: a separate rootless Docker for `claude`

The existing rootful Docker daemon runs **the VPN**, and rootful Docker writes iptables rules
whenever networks/ports are created. So the Matrix stack gets its **own** daemon:

- **Rootless Docker** running as `claude`, as a systemd *user* service.
- **Can't affect the VPN containers:** it can't see the rootful daemon's containers, can't stop
  or prune them, and they can't see it.
- **No host firewall changes:** it never touches the host firewall or routing. Networking lives
  in its own namespace via rootlesskit + slirp4netns, both already installed.
- **Low priority:** the user service runs with `Nice=10` and best-effort IO priority 7, so the
  VPNs always win the CPU. This needs no admin rights.
- **Survives logout:** `loginctl enable-linger claude` keeps it running after logout.
  polkit on this Pi lets claude do that itself.
- **Admin needed (A1):** the `uidmap` package (newuidmap/newgidmap). Everything else is installed.
- **Files outside the project folder:** `~/.config/systemd/user/docker.service` and
  `~/.config/docker/daemon.json`. The docker data-root goes **inside** the project
  (`matrix-hub/.docker-data`) so removal is simple.
- **Known limit:** the kernel's memory cgroup is disabled (`cgroup_enable=memory` missing from
  cmdline.txt), so per-container RAM limits can't be enforced. With 7 GiB free I recommend
  **living with it** instead of editing boot config + rebooting. We keep apps small by config
  and watch RAM.

## 2. Architecture

```
 LAN browser ──https://192.168.0.129:8443──▶ ┌─────────── rootless Docker (user claude) ──────────┐
                                             │ caddy  :8443 (only published port)                 │
                                             │   ├─ /            → element-web (static)            │
                                             │   └─ /_matrix, /_synapse/client → synapse:8008      │
                                             │ synapse ── postgres (DBs: synapse, wa, discord_*)   │
                                             │   ▲ appservice API (internal only)                  │
                                             │ mautrix-whatsapp   mautrix-discord-<a> / -<b>       │
                                             └──────────────── outbound HTTPS only ───────────────┘
```

| Service | Image (pin) | Arch used | Published |
|---|---|---|---|
| postgres | `postgres:17.x-alpine` (exact patch pinned at build) | arm64 | no |
| synapse | `matrixdotorg/synapse:v1.162.0` | arm64 | no |
| element-web | `vectorim/element-web:v1.12.30` | arm64 | no |
| caddy | `caddy:2.11.7-alpine` | arm64 (arm/v7 also exists) | **192.168.0.129:8443/tcp** |
| mautrix-whatsapp | `dock.mau.dev/mautrix/whatsapp:v0.2609.0` | arm64 | no |
| mautrix-discord ×2 | `dock.mau.dev/mautrix/discord:v0.7.7` | arm64 | no |

- **All arm64:** every service uses one shared compose anchor: `platform: linux/arm64` + the
  seccomp profile.
- **Postgres choice:** mautrix bridges recommend Postgres and Synapse discourages SQLite in
  production. One Postgres instance holds one database + role per service.
- **Why Synapse:** lighter Rust homeservers (continuwuity/tuwunel) exist, but mautrix bridges are
  developed and tested against Synapse. That fits priority #2 (stable, maintainable) better.
  RAM isn't the constraint on this Pi.
- **Synapse config kept small:** federation off, registration off, presence off, URL previews off,
  `caches.global_factor: 0.5`, `trusted_key_servers: []`.

### Ports
- **Only new host port:** `8443/tcp` on 192.168.0.129. Nothing UDP, nothing on 0.0.0.0.
- **Avoided:** 22, 80, 5335, 8581, 8953, 51761, 54096 and the VPN UDP ports (<vpn-port>, <vpn-port>).
  Internal subnets avoid <vpn-subnet>, <vpn-subnet> and 172.17/172.18.
- **Note:** binding to the LAN address doesn't stop VPN clients reaching it (they route to the
  Pi). That's fine for later remote access, and no firewall changes are involved.

### HTTPS (needed by Element Web)
- **Why HTTPS at all:** Element Web needs a secure context (HTTPS) for encryption, except on localhost.
- **Stage 2:** Caddy with its own local CA (`tls internal`) for `192.168.0.129`. You import Caddy's
  root certificate once per device. Easy on desktop browsers.
- **Phones:** Android apps usually ignore user-installed CAs, so for phones I recommend a real
  certificate (see server name, option A). Decided by Stage 8 at the latest.

### Federation: not needed
Bridges are appservices that talk only to your own homeserver, and their traffic to
WhatsApp/Discord is outbound HTTPS. Federation is only for chatting with users on *other Matrix
servers* (e.g. matrix.org). It stays off, and no inbound internet port is ever needed.

## 3. Server name (permanent: it's in every user ID, room ID and bridge database)

Changing it later means building a fresh server and re-logging every bridge. Bridged history in
Matrix would be lost (the chats themselves stay on WhatsApp/Discord).

- **A (recommended): a domain you own** (~€10/yr), e.g. `example.net` → IDs `@you:example.net`.
  - Gives phones a trusted HTTPS cert via DNS-01 with **no** open ports. The DNS record can point
    to the LAN/VPN address.
  - Keeps federation possible if you ever want it.
- **B (free): a private name** such as `hub.home.arpa`. `home.arpa` is reserved for home networks
  (RFC 8375). It works fine with federation off, but federation becomes impossible forever and
  phones need the local-CA route.
- **Not recommended: your dynamic-DNS hostname.**
  - It's a subdomain on a shared domain you don't control, and the owner can revoke it.
  - It's also your VPN endpoint name, which you'd be baking into every ID.

## 4. Discord isolation model: one bridge instance per account (chosen)

**Why:** the current release (v0.7.7) supports exactly **one** Discord login per Matrix user
(the multi-login rewrite is an unreleased branch). The alternatives are:
- **(a)** one instance with a second Matrix account per Discord account. You'd keep switching
  Matrix accounts, and a guild both Discord accounts are in maps to *one shared room*, so it's
  easy to reply from the wrong account.
- **(b)** one instance per Discord account.

**Chosen: (b).** Each instance gets:
- its own appservice registration, database and bot (`@discord_<a>bot`, `@discord_<b>bot`),
- its own ghost-user namespace (`@discord<a>_…`, `@discord<b>_…`).

What that buys:
- **Separate rooms:** a guild both accounts share becomes *two* rooms, each tied to one account.
  You can't send from the wrong account in a room.
- **Labels everywhere:** room names are prefixed with the account label, e.g.
  `[personal] #general` / `[gaming] #general`, and ghost names get a suffix. Each instance's
  space is renamed "Discord · <label>".
- **Isolated failures:** a crash, ban or re-login on one account doesn't touch the other.
- **Cost:** ~40–80 MB RAM per instance.

Only guilds you explicitly bridge (`guilds bridge <id>`) are pulled in; DMs come automatically.

### Discord ToS risk (plain terms)
- **What the bridge does:** it logs in *as you* (QR code or user token). Discord classes that as a
  "self-bot", which its terms forbid.
- **What can happen:** typical outcomes range from nothing, to forced captcha/re-login, to
  disabled accounts. Bans are uncommon for low-volume personal use, but there's no guarantee.
- **Mitigations:**
  - Bridge few guilds.
  - Keep backfill small.
  - Don't run bots or automation through it.
  - The Pi uses your home IP, which looks like normal use.
  - Bridge your least important account first and watch it for a week before adding the main one.

### WhatsApp risk
- **How it connects:** mautrix-whatsapp (v0.2609.0, newer framework, actively maintained) is an
  unofficial "linked device".
- **Ban risk:** low for normal personal use. It's higher with mass messaging.
- **Keep the phone online:** your phone must come online at least every ~14 days or the link drops.

## 5. Resource estimate (no hard limits possible, see §1)

| Item | RAM (typical) |
|---|---|
| rootless dockerd + containerd + slirp | 80–120 MB |
| postgres | 60–120 MB |
| synapse | 250–450 MB |
| caddy + element-web | 30–50 MB |
| mautrix-whatsapp | 40–80 MB |
| mautrix-discord ×2 | 80–160 MB |
| **Total** | **≈0.55–1.0 GB of 7.6 GB** |

- **CPU:** near idle once synced. Short spikes on Synapse start and on first bridge sync.
- **Disk:** ~2 GB for images, plus database/media growth. Media retention is set in Synapse.
- **SD card writes:** Postgres is the main writer. Backups go off the card (Stage 3 decides where).

## 6. Layout on the Pi

```
/home/claude/projects/matrix-hub/        (git repo; secrets + data gitignored)
  compose.yaml            core: postgres, synapse, element, caddy; `include:`s each bridge
  seccomp-arm64.json      Docker default profile + AARCH64
  .env                    secrets (chmod 600)
  hub.sh                  start | stop | status | logs | backup | remove
  synapse/  caddy/  element/
  bridges/<name>/compose.yaml + config.yaml + registration.yaml
  data/                   postgres, synapse media, bridge state (gitignored)
  .docker-data/           rootless docker data-root (gitignored)
```

**Adding a bridge** = new `bridges/<name>/` folder + one `include:` line + one database +
one registration line in homeserver.yaml + Synapse restart.

### Stop / remove (documented in PROJECT_NOTES.md once built)
- **Stop everything:** `systemctl --user stop docker.service docker.socket`
  (only claude's rootless daemon. The rootful daemon / the VPN are untouched).
- **Remove:** `./hub.sh remove`, which runs `compose down` + `dockerd-rootless-setuptool.sh uninstall`.
  It then asks before deleting `data/` and `.docker-data/`.

## 7. What needs admin (details in NEEDS_ADMIN.md)
1. **C3:** diagnostic: confirm the seccomp hypothesis.
2. **A1:** `sudo apt install uidmap`.
3. **A2:** stop + delete the old `/home/pi/matrix` experiment (it's crash-looping now).
4. **Later, optional:** DHCP reservation for 192.168.0.129 on your router (needs your approval
   for that specific router change).

Not requested, and recommended against: enabling the memory cgroup (boot config edit + reboot),
or adding claude to the docker group.

## 8. What could go wrong
- **The seccomp fix doesn't work** → fallback is a 64-bit OS reinstall (your decision, VPN downtime).
- **Rootless networking (slirp4netns 1.0.1) is slow** → only matters for big media; fine for chat.
- **No RAM limits** → if something leaks, the OOM killer picks the largest process (Synapse),
  not the VPN. Mitigated by small caches and a status check in `hub.sh`.
- **The Pi's LAN IP changes** → Element URL/cert break → DHCP reservation recommended.
- **SD card corruption** → backups stored off the Pi (Stage 3).
- **Bridge accounts** get logged out or flagged (see §4).

## 9. VPN health check (run after every stage that starts something)
As `pi` on the Pi:
```sh
docker ps --filter name=<vpn-container> --format '{{.Names}} {{.Status}}'   # expect: Up …
<check the VPN handshakes>                                     # recent timestamps for active peers
```
From a phone on mobile data: connect each VPN and load a web page.

## 10. Decisions I need from you
1. Server name: A (which domain?) or B (`hub.home.arpa`, or your pick).
2. Short labels for the two Discord accounts (e.g. `personal`, `gaming`). Which one is the low-risk test account?
3. Use `/srv/homeserver` for anything (e.g. local backup copies), or ignore it?
