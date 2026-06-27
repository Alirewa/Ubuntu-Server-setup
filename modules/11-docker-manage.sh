#!/usr/bin/env bash
# 11-docker-manage.sh — see at a glance which containers svsetup (and anything
# else) installed are running, and which host ports each one occupies, with
# basic start/stop/restart/logs/remove actions. Pure `docker` wrapper.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

module_docker_manage() {
  command -v docker >/dev/null 2>&1 || die "Docker is not installed yet — run option 1 first."
  while true; do
    clear
    header "Docker Container Management"
    list_containers
    echo
    echo "  1) Start a container"
    echo "  2) Stop a container"
    echo "  3) Restart a container"
    echo "  4) View logs (last 100 lines)"
    echo "  5) Remove a container (image/volumes are kept)"
    echo "  6) Show every host port Docker currently publishes"
    echo "  7) Show disk usage (images/containers/volumes)"
    echo "  0) Back to main menu"
    echo
    local c
    ask c "Choose" "0"
    case "$c" in
      1) with_container "Start which container?" docker start ;;
      2) with_container "Stop which container?" docker stop ;;
      3) with_container "Restart which container?" docker restart ;;
      4) with_container "Logs for which container?" docker logs --tail 100 ;;
      5) remove_container ;;
      6) show_all_ports; press_enter ;;
      7) docker system df; press_enter ;;
      0) return 0 ;;
      *) warn "Invalid choice" ;;
    esac
  done
}

list_containers() {
  printf '%-22s %-10s %-22s %s\n' "NAME" "STATE" "PORTS" "IMAGE"
  printf '%-22s %-10s %-22s %s\n' "----" "-----" "-----" "-----"
  docker ps -a --format '{{.Names}}|{{.State}}|{{.Ports}}|{{.Image}}' | \
    while IFS='|' read -r name state ports image; do
      printf '%-22s %-10s %-22s %s\n' "$name" "$state" "${ports:-none}" "$image"
    done
}

with_container() {
  local prompt="$1"; shift
  local name
  ask name "$prompt (exact container name, blank to cancel)" ""
  [ -z "$name" ] && return 0
  if docker "$@" "$name"; then
    ok "Done: $* ${name}"
  else
    warn "Failed to run '$* ${name}' — check the container name above"
  fi
  press_enter
}

remove_container() {
  local name
  ask name "Remove which container? (blank to cancel)" ""
  [ -z "$name" ] && return 0
  confirm "Remove container '${name}'? Its image and named volumes are kept." "N" || return 0
  docker rm -f "$name" >/dev/null 2>&1 && ok "Removed ${name}" || warn "Failed to remove ${name}"
  press_enter
}

show_all_ports() {
  header "Host ports currently published by Docker"
  docker ps --format '{{.Names}}' | while read -r name; do
    local ports
    ports="$(docker port "$name" 2>/dev/null)"
    [ -n "$ports" ] && { echo "${name}:"; echo "$ports" | sed 's/^/  /'; }
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  require_root; require_ubuntu
  module_docker_manage
fi
