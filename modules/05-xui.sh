#!/usr/bin/env bash
# 05-xui.sh — 3x-ui (MHSanaei) installed via Docker, following the official
# docker-compose.yml/Dockerfile shipped in the project's own repo. A thin
# host-side `x-ui` shim proxies into the container so the native management
# console (domain binding, SSL certs via acme.sh, settings) works exactly
# like it did on a native install — just `docker exec -it` underneath.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

XUI_REPO_URL="https://github.com/MHSanaei/3x-ui.git"
XUI_INSTALL_DIR="/opt/3x-ui"
XUI_CONTAINER="3xui_app"
XUI_DEFAULT_PORT=2080
XUI_DEFAULT_WEBPATH="webdw"
XUI_DEFAULT_USERNAME="admin"
XUI_DEFAULT_PASSWORD="admin"
XUI_PORT_RANGE_START=2080
XUI_PORT_RANGE_END=2090
XUI_CPUS="${SVSETUP_XUI_CPUS:-0.5}"
XUI_MEM="${SVSETUP_XUI_MEM:-512m}"

module_xui() {
  while true; do
    clear
    header "3x-ui (Sanaei panel)"
    xui_status_line
    echo
    echo "  1) Install / update (build latest from source)"
    echo "  2) Domain & SSL certificate (opens the native x-ui console)"
    echo "  3) Login settings (username / password / port / web path)"
    echo "  4) Show status & URL"
    echo "  5) Remove 3x-ui"
    echo "  0) Back to main menu"
    echo
    local c
    ask c "Choose" "0"
    case "$c" in
      1) xui_install_or_update; press_enter ;;
      2) xui_console ;;
      3) xui_quick_settings ;;
      4) xui_show_status; press_enter ;;
      5) if command -v reset_xui >/dev/null 2>&1; then
           reset_xui
         else
           warn "Run this from the main svsetup menu (or: sudo svsetup --reset) to remove it."
         fi
         press_enter ;;
      0) return 0 ;;
      *) warn "Invalid choice" ;;
    esac
  done
}

xui_installed() { [ -f "${XUI_INSTALL_DIR}/docker-compose.yml" ]; }

xui_running() {
  docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$XUI_CONTAINER"
}

xui_status_line() {
  if ! xui_installed; then
    info "Not installed yet."
    return 0
  fi
  if xui_running; then
    ok "Installed and running."
  else
    warn "Installed but the container is not running."
  fi
}

xui_install_or_update() {
  ensure_docker
  header "3x-ui — install / update"
  info "Following the official Docker install method from the 3x-ui repo itself"
  info "(docker-compose.yml + Dockerfile at the repo root, built locally)."

  local first_install=true
  xui_installed && first_install=false

  fetch_xui_source
  if $first_install; then
    write_xui_compose "$XUI_DEFAULT_PORT" "$XUI_DEFAULT_WEBPATH"
  fi
  build_and_start_xui
  if $first_install; then
    enforce_xui_settings "$XUI_DEFAULT_USERNAME" "$XUI_DEFAULT_PASSWORD" "$XUI_DEFAULT_PORT" "$XUI_DEFAULT_WEBPATH"
  fi
  install_xui_host_shim

  header "Firewall: opening the 3x-ui port range"
  ufw_allow "${XUI_PORT_RANGE_START}:${XUI_PORT_RANGE_END}/tcp" "3x-ui"
  ufw_allow "${XUI_PORT_RANGE_START}:${XUI_PORT_RANGE_END}/udp" "3x-ui"
  ok "Opened ${XUI_PORT_RANGE_START}-${XUI_PORT_RANGE_END} (tcp+udp) — panel + inbounds + SSL cert challenges"

  append_info_doc <<EOF

== [05] 3x-ui (Docker) ==
Source:    ${XUI_INSTALL_DIR} (cloned from MHSanaei/3x-ui, built into a local image)
Container: ${XUI_CONTAINER}
Console:   type 'x-ui' on the host (proxies to 'docker exec -it ${XUI_CONTAINER} x-ui') —
           same menu as a native install: domain binding, SSL certs via acme.sh,
           settings, restart, etc. Use svsetup's "3x-ui" menu for the same actions.
Ports:     ${XUI_PORT_RANGE_START}-${XUI_PORT_RANGE_END} (tcp+udp) published from the
           container AND opened in the firewall — covers the panel, future Xray
           inbounds, and acme.sh's HTTP-01 challenge listener if you request a
           domain certificate (pick a free port in this range when asked).
Resource priority vs Coolify: this container is capped at cpus=${XUI_CPUS},
mem_limit=${XUI_MEM} directly in its docker-compose.yml (plain Docker resource
limits — Coolify's containers are simply left uncapped).
EOF

  mark_done "xui"
  ok "3x-ui (Docker) ready. Type 'x-ui' on the host any time for the full console."
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

# write_xui_compose PORT WEBPATH — (re)generates the compose file. Always
# publishes the full reserved port range (covers inbounds and acme.sh
# challenges); adds the panel port explicitly too if it's outside that range.
write_xui_compose() {
  local port="$1" webpath="$2"
  local extra_port=""
  if [ "$port" -lt "$XUI_PORT_RANGE_START" ] || [ "$port" -gt "$XUI_PORT_RANGE_END" ]; then
    extra_port="      - \"${port}:${port}/tcp\""
  fi
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
      XUI_PORT: "${port}"
      XUI_INIT_WEB_BASE_PATH: "${webpath}"
    tty: true
    ports:
      - "${XUI_PORT_RANGE_START}-${XUI_PORT_RANGE_END}:${XUI_PORT_RANGE_START}-${XUI_PORT_RANGE_END}/tcp"
      - "${XUI_PORT_RANGE_START}-${XUI_PORT_RANGE_END}:${XUI_PORT_RANGE_START}-${XUI_PORT_RANGE_END}/udp"
$([ -n "$extra_port" ] && printf '%s\n' "$extra_port")
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

# install_xui_host_shim — restores the plain `x-ui` command on the HOST,
# proxying into the container, so it behaves exactly like a native install.
install_xui_host_shim() {
  cat > /usr/local/bin/x-ui <<EOF
#!/usr/bin/env bash
exec docker exec -it ${XUI_CONTAINER} x-ui "\$@"
EOF
  chmod +x /usr/local/bin/x-ui
  ok "Host command 'x-ui' restored (proxies into the container)"
}

# enforce_xui_settings USER PASS PORT WEBPATH — sets credentials/port/path via
# the panel's own CLI. Idempotent: safe to call again with the same values.
enforce_xui_settings() {
  local user="$1" pass="$2" port="$3" webpath="$4" tries=0
  until docker exec "$XUI_CONTAINER" /app/x-ui setting \
      -username "$user" -password "$pass" \
      -port "$port" -webBasePath "$webpath" >/dev/null 2>&1; do
    tries=$((tries + 1))
    if [ "$tries" -ge 10 ]; then
      warn "Could not confirm x-ui settings via CLI — the panel may still be starting."
      warn "Defaults (admin/admin, port ${port}, /${webpath}/) should already apply from first boot."
      return 0
    fi
    sleep 2
  done
  docker restart "$XUI_CONTAINER" >/dev/null 2>&1 || true
  ok "Credentials/port/web-path set: ${user}/${pass}, port ${port}, /${webpath}/"
}

# xui_console — opens the exact same interactive menu as the host `x-ui`
# command and a native install: domain binding, SSL certs via acme.sh
# (Let's Encrypt, domain or IP-based), settings, restart, etc.
xui_console() {
  if ! xui_installed; then
    warn "3x-ui isn't installed yet — use option 1 first."
    press_enter
    return 0
  fi
  if ! xui_running; then
    warn "Container isn't running — starting it..."
    if ! ( cd "$XUI_INSTALL_DIR" && docker compose up -d ); then
      warn "Could not start the container."
      press_enter
      return 0
    fi
  fi
  echo
  info "Opening the native x-ui console (domain binding, SSL certs via acme.sh, settings)."
  info "Requesting a Let's Encrypt cert needs a port reachable from the internet for the"
  info "HTTP-01 challenge — pick a free port in ${XUI_PORT_RANGE_START}-${XUI_PORT_RANGE_END}"
  info "when asked (that whole range is already published and open in the firewall)."
  press_enter
  docker exec -it "$XUI_CONTAINER" x-ui || warn "Console exited with an error."
  press_enter
}

xui_quick_settings() {
  if ! xui_installed; then
    warn "3x-ui isn't installed yet — use option 1 first."
    press_enter
    return 0
  fi
  local current current_port current_path new_user new_pass new_port new_path
  current="$(docker exec "$XUI_CONTAINER" /app/x-ui setting -show true 2>/dev/null)" || current=""
  current_port="$(printf '%s\n' "$current" | grep -Eo 'port: .+' | awk '{print $2}')"
  current_path="$(printf '%s\n' "$current" | grep -Eo 'webBasePath: .+' | awk '{print $2}' | tr -d '/')"

  ask new_user "Admin username" "$XUI_DEFAULT_USERNAME"
  ask new_pass "Admin password" "$XUI_DEFAULT_PASSWORD"
  ask new_port "Panel port" "${current_port:-$XUI_DEFAULT_PORT}"
  ask new_path "Web base path (no slashes, e.g. webdw)" "${current_path:-$XUI_DEFAULT_WEBPATH}"

  if [ "$new_port" != "${current_port:-$XUI_DEFAULT_PORT}" ]; then
    info "Port changed — regenerating the Docker port mapping..."
    write_xui_compose "$new_port" "$new_path"
    ( cd "$XUI_INSTALL_DIR" && docker compose up -d )
    ufw_allow "${new_port}/tcp" "3x-ui (custom port)"
  fi
  enforce_xui_settings "$new_user" "$new_pass" "$new_port" "$new_path"
  ok "Panel: http://<server-ip>:${new_port}/${new_path}/"
  press_enter
}

xui_show_status() {
  if ! xui_installed; then
    info "3x-ui is not installed."
    return 0
  fi
  if xui_running; then
    ok "Container ${XUI_CONTAINER} is running"
  else
    warn "Container ${XUI_CONTAINER} exists but is not running"
    return 0
  fi
  docker exec "$XUI_CONTAINER" /app/x-ui setting -show true 2>/dev/null || \
    warn "Could not query panel settings (it may still be starting)."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  require_root; require_ubuntu
  module_xui
fi
