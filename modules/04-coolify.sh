#!/usr/bin/env bash
# 04-coolify.sh — Coolify install (latest, official installer) + firewall ports +
# performance helpers so deployed sites load fast. Coolify gets resource priority
# over every other panel installed by svsetup.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

COOLIFY_INSTALLER_URL="https://raw.githubusercontent.com/Alirewa/coolify-Persian-optimize-/v4.x/scripts/install.sh"
COOLIFY_PORTS=(22 80 443 8000 6001 6002)
COOLIFY_APP_PORT_RANGE_START=3000
COOLIFY_APP_PORT_RANGE_END=3020

module_coolify() {
  ensure_docker

  header "Coolify"
  if command -v coolify >/dev/null 2>&1 || [ -d /data/coolify ]; then
    ok "Coolify already installed, re-running the installer to update to latest"
  else
    info "Installing Coolify from your fork's installer (always pulls its latest commit)..."
  fi

  header "Firewall: ports needed before install"
  for p in "${COOLIFY_PORTS[@]}"; do ufw_allow "${p}/tcp" "Coolify"; done
  ufw_allow "${COOLIFY_APP_PORT_RANGE_START}:${COOLIFY_APP_PORT_RANGE_END}/tcp" "Coolify apps"
  ok "Opened: ${COOLIFY_PORTS[*]}, and ${COOLIFY_APP_PORT_RANGE_START}-${COOLIFY_APP_PORT_RANGE_END} for app ports"
  ask_open_ports "Coolify (e.g. a custom port for one of your deployed apps)"

  run_remote_installer "$COOLIFY_INSTALLER_URL"
  ok "Coolify install/update finished"

  header "Performance helpers for faster deployed sites"
  enable_buildkit_cache

  append_info_doc <<'EOF'

== [04] Coolify ==
Installed from: Alirewa/coolify-Persian-optimize- (v4.x branch), not upstream coollabs.
Dashboard: http://<server-ip>:8000  (set up your admin account on first visit)
Ports opened: 80 (HTTP), 443 (HTTPS), 8000 (dashboard), 6001/6002 (realtime websockets),
and 3000-3020 reserved for apps you deploy that need a port of their own
(e.g. a custom backend service) — no extra firewall step needed for those.

Why deployed sites can feel slow right after a deploy, and what was done about it:
  1. Cold start: a fresh deploy rebuilds the container image and starts a brand-new
     process — the first request after deploy is always slower. This is normal and
     no package fixes it; it's the cost of an immutable-image deploy model.
  2. Build speed: Docker BuildKit + a persistent build-cache volume were enabled
     (see [03] Docker) so repeat deploys reuse cached layers instead of rebuilding
     everything — this is the biggest real lever for "Coolify deploy is slow".
  3. Network: BBR congestion control + larger TCP backlogs (see [01]) measurably
     speed up first-byte time and asset downloads, especially for visitors far from
     the server.
  4. We deliberately did NOT install a second web server (nginx/apache/caddy) in
     front of Coolify — Coolify already runs its own Traefik proxy on 80/443, and a
     second proxy would only add latency or fight Traefik for those ports.
  5. For a real, durable speed win on top of this: put your domain behind a CDN
     (Cloudflare free tier is the common choice) — that's an edge-cache problem,
     not a server-package problem, and no Ubuntu package can fully substitute for it.

Resource priority: Coolify's Docker containers are left UNCAPPED (no cpus/mem limits).
x-ui's container is capped via cpus/mem_limit in its own docker-compose.yml instead — see [05].
EOF

  mark_done "coolify"
  ok "Coolify setup complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  require_root; require_ubuntu
  module_coolify
fi
