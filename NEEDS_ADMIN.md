# Commands that need you (admin / docker group)

Nothing here has been run by Claude. Review each, then run it as `pi` (or with sudo where shown).

## Stage 0 — done
- C1 (arm64 test): image pulled, `uname -m` printed **nothing** → container killed (see C3).
- C2: found `<vpn-container>` (Up), `matrix-synapse-1` (crash loop, exit 159), `matrix-postgres-1` (Up),
  network `matrix_default`, no volumes.

## Stage 1 — please run

**C3. Confirm the seccomp diagnosis** (as `pi`; read-only, diagnostic only):
```sh
docker run --rm --platform linux/arm64 alpine:3.20 uname -m; echo "exit=$?"
docker run --rm --platform linux/arm64 --security-opt seccomp=unconfined alpine:3.20 uname -m; echo "exit=$?"
docker image rm alpine:3.20
```
Expected if I'm right: first prints `exit=159`, second prints `aarch64` and `exit=0`.
Seccomp is disabled only for that one throwaway test container. The real stack will use a
proper profile instead.

**A2. Remove the old Matrix experiment** (you authorised deleting it):
```sh
cd /home/pi/matrix && docker compose down      # stops/removes only project "matrix": its 2 containers + matrix_default network
sudo rm -rf /home/pi/matrix                    # sudo needed: postgres/ is owned by uid 999 (container user)
docker image rm matrixdotorg/synapse:latest postgres:16
```
- **Scope:** `compose down` only acts on the `matrix` project. The `<vpn-container>` container is a
  different project and is not touched.
- **Side effect:** removing `matrix_default` makes Docker delete its own iptables rules for that network.
- **Why bother:** Synapse is crash-looping now (wasted CPU).

## After you approve the plan

**A1. Install `uidmap`** (needed for rootless Docker):
```sh
sudo apt-get install --no-install-recommends uidmap
```
- **Why:** rootless Docker needs the setuid helpers `newuidmap`/`newgidmap` to map claude's
  sub-UID range (165536–231071, already in /etc/subuid) into containers.
- **What it is:** a tiny shadow-utils package. No services, no network changes, no restarts.

## Optional / later
- **DHCP reservation** for the Pi (192.168.0.129) on your router, so the Element URL and
  certificate stay valid. Router change: only if you approve it.
