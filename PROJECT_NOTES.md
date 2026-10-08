# matrix-hub — project notes

Self-hosted Matrix hub (Synapse + Element + mautrix bridges) on the home Pi.
Work dir on Pi: `/home/claude/projects/matrix-hub` (local mirror: `C:\pi-work\matrix-hub`).

## Status
- 2026-10-07 — Stage 0 (audit) done. Nothing installed, nothing running, no ports opened.
- 2026-10-07 — Stage 1 plan written (PLAN.md), **awaiting approval** + checks C3/A2.
  The user authorised deleting/restarting the old `/home/pi/matrix` experiment.

## Decisions (see PLAN.md for reasoning)
- Federation: off (not needed for bridges). Registration: closed.
- Containers: separate **rootless Docker** as claude; the rootful daemon (runs the VPN) is never used.
- All arm64 images + custom seccomp profile (pending C3 confirmation).
- Synapse + Postgres; Caddy (internal CA) serves Element + proxies Synapse on 192.168.0.129:8443.
- Discord: one mautrix-discord instance per account.
- Server name: pending (own domain recommended; `hub.home.arpa` fallback; not the dynamic-DNS hostname).

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
