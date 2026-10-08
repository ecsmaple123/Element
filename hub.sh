#!/usr/bin/env bash
# Control script for matrix-hub. Talks ONLY to claude's rootless Docker daemon;
# the system Docker daemon (which runs the VPN) is never used.
set -euo pipefail
cd "$(dirname "$0")"
export DOCKER_HOST="${DOCKER_HOST:-unix:///run/user/$(id -u)/docker.sock}"

usage() {
  cat <<EOF
Usage: ./hub.sh <command>
  up              start/update the stack
  stop            stop all containers (data kept)
  down            stop and remove containers (data kept)
  status          containers, health, CPU/RAM
  logs [service]  follow logs
  adduser         create a Matrix user (interactive; asks for name/password/admin)
  backup          back up databases + files to backups/ (keeps newest 7)
  restore <dir>   restore a backup into this folder (fresh machine; see PROJECT_NOTES.md)
  daemon-stop     stop claude's rootless Docker daemon entirely (stops everything)
  daemon-start    start it again
  remove          tear everything down, uninstall rootless Docker (asks first)
EOF
}

case "${1:-}" in
  up)      docker compose up -d ;;
  stop)    docker compose stop ;;
  down)    docker compose down ;;
  status)  docker compose ps
           echo
           docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}' ;;
  logs)    shift; docker compose logs --tail=100 -f "$@" ;;
  backup)  scripts/backup.sh ;;
  restore) shift; scripts/restore.sh "$@" ;;
  adduser) docker compose exec synapse register_new_matrix_user \
             -c /data/secrets.yaml http://localhost:8008 ;;
  daemon-stop)  systemctl --user stop docker.service docker.socket ;;
  daemon-start) systemctl --user start docker.service ;;
  remove)
    echo "This removes ALL matrix-hub containers, the database volume and claude's rootless Docker."
    echo "VPNs and the system Docker daemon are not affected. Take a backup first."
    read -rp "Type REMOVE to continue: " ans
    [[ "$ans" == "REMOVE" ]] || { echo "Aborted."; exit 1; }
    systemctl --user disable --now matrixhub-backup.timer 2>/dev/null || true
    rm -f ~/.config/systemd/user/matrixhub-backup.{service,timer}
    docker compose down -v --rmi all || true
    systemctl --user disable --now docker.service docker.socket || true
    PATH=/usr/sbin:/sbin:$PATH dockerd-rootless-setuptool.sh uninstall -f || true
    # data-root files belong to sub-UIDs; delete them from inside the user namespace.
    rootlesskit rm -rf .docker-data
    echo "Removed. Config + data/ (Synapse media, Caddy CA, secrets) are left in $(pwd);"
    echo "delete the folder yourself if you want them gone: rm -rf $(pwd)"
    echo "Also left: ~/.config/docker/daemon.json and ~/.config/systemd/user/docker.service.d/"
    ;;
  *) usage; exit 1 ;;
esac
