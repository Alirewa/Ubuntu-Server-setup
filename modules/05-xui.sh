#!/usr/bin/env bash
# 05-xui.sh — 3x-ui (MHSanaei) installed via Docker, following the official
# docker-compose.yml shipped in the project's own repo. Fixed admin/admin
# credentials, fixed port, fixed web path, fixed port range — no prompts.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

XUI_REPO_URL="https://github.com/MHSanaei/3x-ui.git"
XUI_INSTALL_DIR="/opt/3x-ui"
XUI_CONTAINER="3xui_app"
XUI_PORT="${SVSETUP_XUI_PORT:-2080}"
XUI_WEBPATH="${SVSETUP_XUI_WEBPATH:-webdw}"
XUI_USERNAME="${SVSETUP_XUI_USERNAME:-admin}"
XUI_PASSWORD="${SVSETUP_XUI_PASSWORD:-admin}"
XUI_PORT_RANGE_START=2080
XUI_PORT_RANGE_END=2090
XUI_CPUS="${SVSETUP_XUI_CPUS:-0.5}"
XUI_MEM="${SVSETUP_XUI_MEM:-512m}"

module_xui() {
  ensure_docker

  header "3x-ui (Sanaei panel) — Docker install"
  info "Following the official Docker install method from the 3x-ui repo itself"
  info "(docker-compose.yml + Dockerfile at the repo root, built locally)."

  fetch_xui_source
  write_xui_compose
  build_and_start_xui
  enforce_xui_settings

  header "Firewall: opening the 3x-ui port range"
  ufw_allow "${XUI_PORT_RANGE_START}:${XUI_PORT_RANGE_END}/tcp" "3x-ui"
  ufw_allow "${XUI_PORT_RANGE_START}:${XUI_PORT_RANGE_END}/udp" "3x-ui"
  ok "Opened ${XUI_PORT_RANGE_START}-${XUI_PORT_RANGE_END} (tcp+udp) — panel + future inbounds"

  append_info_doc <<EOF

== [05] 3x-ui (Docker) ==
Panel:    http://<server-ip>:${XUI_PORT}/${XUI_WEBPATH}/
Login:    ${XUI_USERNAME} / ${XUI_PASSWORD}   <-- change this from inside the panel
Source:   ${XUI_INSTALL_DIR} (cloned from MHSanaei/3x-ui, built into a local image)
Container: ${XUI_CONTAINER}   |   Manage: docker compose -f ${XUI_INSTALL_DIR}/docker-compose.yml ...
Ports opened: ${XUI_PORT_RANGE_START}-${XUI_PORT_RANGE_END} (tcp+udp) — covers the panel port
and leaves headroom for Xray inbounds you add later in that same range, with no extra
firewall prompts needed.

Resource priority vs Coolify: this container is capped at cpus=${XUI_CPUS},
mem_limit=${XUI_MEM} directly in its docker-compose.yml (plain Docker resource
limits, same mechanism Coolify's own containers use — they're just left uncapped).

Update later: cd ${XUI_INSTALL_DIR} && git pull && docker compose up -d --build
EOF

  mark_done "xui"
  ok "3x-ui (Docker) setup complete — panel at http://<server-ip>:${XUI_PORT}/${XUI_WEBPATH}/"
}

fetch_xui_source() {
  if [ -d "${XUI_INSTALL_DIR}/.git" ]; then
    info "Updating existing 3x-ui source checkout..."
    git -C "$XUI_INSTALL_DIR" fetch --all -q
    git -C "$XUI_INSTALL_DIR" reset --hard origin/main -q
  else
    info "Cloning 3x-ui source (first build compiles Go + the frontend inside Docker —"
    info "this can take several minutes and needs ~1-2GB free RAM during the build)..."
    git clone -q "$XUI_REPO_URL" "$XUI_INSTALL_DIR"
  fi
  mkdir -p "${XUI_INSTALL_DIR}/db" "${XUI_INSTALL_DIR}/cert"
}

write_xui_compose() {
  cat > "${XUI_INSTALL_DIR}/docker-compose.yml" <<EOF
services:
  3xui:
    build:
      context: .
      dockerfile: ./Dockerfile
    container_name: ${XUI_CONTAINER}
    cap_add:
      - NET_ADMIN
      - NET_RAW
    volumes:
      - ./db/:/etc/x-ui/
      - ./cert/:/root/cert/
    environment:
      XRAY_VMESS_AEAD_FORCED: "false"
      XUI_ENABLE_FAIL2BAN: "true"
      XUI_PORT: "${XUI_PORT}"
      XUI_INIT_WEB_BASE_PATH: "${XUI_WEBPATH}"
    tty: true
    ports:
      - "${XUI_PORT}:${XUI_PORT}"
    cpus: "${XUI_CPUS}"
    mem_limit: "${XUI_MEM}"
    restart: unless-stopped
EOF
}

build_and_start_xui() {
  info "Building and starting the 3x-ui container (docker compose up -d --build)..."
  ( cd "$XUI_INSTALL_DIR" && docker compose up -d --build )
  ok "3x-ui container is up"
}

# Locks in admin/admin, the fixed port, and the fixed web path via the panel's
# own CLI — idempotent, so re-running install (e.g. after an update) always
# converges back to these values instead of drifting from a previous run.
enforce_xui_settings() {
  local tries=0
  until docker exec "$XUI_CONTAINER" /app/x-ui setting \
      -username "$XUI_USERNAME" -password "$XUI_PASSWORD" \
      -port "$XUI_PORT" -webBasePath "$XUI_WEBPATH" >/dev/null 2>&1; do
    tries=$((tries + 1))
    if [ "$tries" -ge 10 ]; then
      warn "Could not confirm x-ui settings via CLI — the panel may still be starting."
      warn "Defaults (admin/admin, port ${XUI_PORT}, /${XUI_WEBPATH}/) should already apply from first boot."
      return 0
    fi
    sleep 2
  done
  docker restart "$XUI_CONTAINER" >/dev/null 2>&1 || true
  ok "Credentials/port/web-path locked in: ${XUI_USERNAME}/${XUI_PASSWORD}, port ${XUI_PORT}, /${XUI_WEBPATH}/"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  require_root; require_ubuntu
  module_xui
fi
