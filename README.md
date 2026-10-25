# Element

A self-hosted Matrix chat hub for a Raspberry Pi 4: one inbox for WhatsApp, Discord and Messenger.
It runs Synapse and the Element web client, with mautrix bridges for each network. Everything lives
on the home LAN, and you reach it from outside through your own VPN.

- **Stack:** Synapse, PostgreSQL, Element Web, Caddy (TLS from a local CA), mautrix-whatsapp,
  mautrix-discord (one instance per Discord account), mautrix-meta. All of it runs in
  **rootless Docker** under an unprivileged user, so it stays apart from the system Docker daemon.
- **Server name:** `hub.home.arpa`. Element is served at `https://<pi-lan-ip>:8443`.
- **Phone:** Element X on iOS, with the hub's CA certificate trusted on the device.

## Layout
- `compose.yaml`: the core stack. Each bridge has its own compose file under `bridges/<name>/`.
- `synapse/`, `caddy/`, `element/`, `postgres/`: service config. Secrets and state live in `data/`,
  which is gitignored. `scripts/gen-secrets.sh` creates them.
- `hub.sh`: start, stop, status, logs and backups for the whole hub.
- `scripts/`: backup and restore, a daily backup timer (systemd user units), bridge add and remove
  helpers (`add-bridge.sh`, `new-discord.sh`, `remove-bridge.sh`) and diagnostics.

## Notes
- `PLAN.md` has the original design and the decisions behind it. `PROJECT_NOTES.md` has the status
  log, how-to guides (adding a bridge, choosing which Discord channels are bridged, restoring a
  backup) and lessons learned. `NEEDS_ADMIN.md` lists the steps that needed root.
- Built for a Pi 4 with a 64-bit kernel and 32-bit userland, using arm64 container images.
- Personal setup, published as a reference. Some names in this public copy are replaced by
  placeholders such as `<vpn-port>`.

The name has nothing to do with the official Element project. This repo only deploys their client.
