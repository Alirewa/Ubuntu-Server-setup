#!/usr/bin/env bash
# 09-speed.sh — standalone "make the web stuff load faster" button.
# Re-applies/verifies the network tuning so it can be run any time, independent
# of the full initial setup, and reports what's actually active right now.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

module_speed() {
  header "Web/Network Speed Boost (helps Coolify + 3x-ui load faster)"

  apply_network_tuning
  enable_buildkit_cache
  ensure_swap_present

  echo
  info "Current state:"
  printf '  TCP congestion control: %s\n' "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)"
  printf '  Queueing discipline:    %s\n' "$(sysctl -n net.core.default_qdisc 2>/dev/null || echo unknown)"
  printf '  Swap active:            %s\n' "$(swapon --show 2>/dev/null | grep -q . && echo yes || echo no)"
  if command -v docker >/dev/null 2>&1; then
    printf '  Docker BuildKit cache:   %s\n' "$(docker volume inspect svsetup_buildkit_cache >/dev/null 2>&1 && echo present || echo missing)"
  fi

  append_info_doc <<'EOF'

== [09] Speed Boost ==
Re-applied: TCP BBR congestion control, larger socket backlogs, vm.swappiness=10,
raised file-descriptor limits, and the Docker BuildKit cache volume used by Coolify
deploys. Safe to re-run any time — it only re-asserts these settings, it does not
touch anything Coolify/x-ui manage themselves.

Levers NOT covered here (because no Ubuntu package can fix them):
  - First-request cold start after a fresh Coolify deploy — inherent to rebuilding
    a container image, not a missing setting.
  - Geographic latency to visitors far from this server — only a CDN (e.g.
    Cloudflare) actually fixes that; it's an edge-cache problem, not a server one.
EOF

  mark_done "speed"
  ok "Speed boost applied"
  press_enter
}

ensure_swap_present() {
  swapon --show 2>/dev/null | grep -q . && return 0
  warn "No swap detected — run option 1 (Initial server setup) once to create one."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  require_root; require_ubuntu
  module_speed
fi
