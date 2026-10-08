# matrix-hub — project notes

Self-hosted Matrix hub (Synapse + Element + mautrix bridges) on the home Pi.
Work dir on Pi: `/home/claude/projects/matrix-hub` (local mirror: `C:\pi-work\matrix-hub`).

## Status
- 2026-10-07 — Stage 0 (audit) done. Nothing installed, nothing running, no ports opened.
- 2026-10-07 — Stage 1 plan written (PLAN.md), **awaiting approval** + checks C3/A2.
  The user authorised deleting/restarting the old `/home/pi/matrix` experiment.

- 2026-10-07 — Plan approved. Server name **hub.home.arpa** (permanent). Discord labels: beta, alpha
  (alpha = low-risk test account, bridged first). More Discord accounts may be added later.
  `/srv/homeserver` is ignored. The user deleted the old `/home/pi/matrix` experiment and installed `uidmap`.
- 2026-10-07 — **Stage 2 (core) running.** Admin user + Element login: waiting on the user.

## Running now (Stage 2)
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
- **Remove completely (one command):** `./hub.sh remove`. It asks for confirmation, then removes the containers,
  the database volume, images and rootless Docker. The system Docker daemon / the VPNs are untouched.
- None of these touch the VPNs: different daemon, no firewall/routing changes.

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
