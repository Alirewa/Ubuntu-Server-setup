#!/usr/bin/env bash
# 05-xui.sh — 3x-ui (MHSanaei) latest install via the project's own interactive
# installer, then firewall + resource capping so it never competes with Coolify.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

COOLIFY_RESERVED_PORTS="22 80 443 8000 6001 6002"

module_xui() {
  header "3x-ui (Sanaei panel)"
  warn "The official installer will ask you to choose/confirm a panel port and"
  warn "credentials. Avoid these Coolify-reserved ports: ${COOLIFY_RESERVED_PORTS}"
  press_enter

  run_remote_installer "https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh"
  ok "3x-ui install/update finished"

  header "Firewall: open the ports x-ui is using"
  open_xui_ports

  header "Resource priority: capping x-ui so Coolify stays at ~80% of resources"
  cap_xui_resources

  append_info_doc <<'EOF'

== [05] 3x-ui ==
Manage from the shell at any time with: x-ui
(menu lets you change port/credentials, view inbounds, restart, etc.)

Resource priority vs Coolify:
  Coolify runs as plain Docker containers with NO resource limits, so the Docker
  scheduler always gives it whatever CPU/RAM it asks for. x-ui, however, is installed
  natively (not in a container) as the systemd service `x-ui.service`, so a Docker
  cgroup limit cannot apply to it directly — the equivalent systemd mechanism
  (CPUQuota + MemoryMax, the same cgroup v2 controls Docker itself uses under the
  hood) was applied instead, capping x-ui at roughly 20% CPU / 512MB RAM and a lower
  scheduling/IO priority (Nice=10). Net effect: Coolify gets effective priority for
  the remaining ~80% of resources, matching what you asked for.
  Adjust the cap any time: edit /etc/systemd/system/x-ui.service.d/svsetup-limits.conf
  then run: systemctl daemon-reload && systemctl restart x-ui
EOF

  mark_done "xui"
  ok "3x-ui setup complete"
}

open_xui_ports() {
  local port
  ask port "Panel port you just set in the x-ui installer (for the firewall rule)" ""
  if [ -n "$port" ]; then
    ufw_allow "${port}/tcp" "3x-ui panel"
    ok "Opened panel port ${port}/tcp"
  else
    warn "No port entered — open it manually later with: ufw allow <port>/tcp"
  fi
  if confirm "Will you add VPN inbounds on additional ports (besides the panel)?" "N"; then
    local range
    ask range "Port or range to open (e.g. 443 or 10000:10100)" ""
    [ -n "$range" ] && ufw_allow "${range}/tcp" "3x-ui inbound" && ufw_allow "${range}/udp" "3x-ui inbound"
  fi
}

cap_xui_resources() {
  local cpu_pct mem_cap
  cpu_pct="${SVSETUP_XUI_CPU_PCT:-20%}"
  mem_cap="${SVSETUP_XUI_MEM:-512M}"
  mkdir -p /etc/systemd/system/x-ui.service.d
  cat > /etc/systemd/system/x-ui.service.d/svsetup-limits.conf <<EOF
[Service]
CPUQuota=${cpu_pct}
MemoryMax=${mem_cap}
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
EOF
  systemctl daemon-reload
  systemctl restart x-ui >/dev/null 2>&1 || true
  ok "x-ui capped at CPUQuota=${cpu_pct}, MemoryMax=${mem_cap}, low scheduling priority"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  require_root; require_ubuntu
  module_xui
fi
