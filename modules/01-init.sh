#!/usr/bin/env bash
# 01-init.sh — Base system update, hardware-aware performance tuning.
# Runs automatically on a fresh server (and is safe to re-run).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

module_init() {
  header "System Update & Base Packages"
  apt_update_once
  info "Upgrading installed packages (this can take a few minutes on a fresh server)..."
  DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq
  DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y -qq
  ok "System packages up to date"

  info "Installing base toolchain..."
  pkg_install curl wget git unzip zip tar gnupg lsb-release ca-certificates \
    software-properties-common apt-transport-https build-essential \
    chrony cron
  ok "Base toolchain installed"

  header "Timezone & Locale"
  if ! is_done "timezone"; then
    local tz="${SVSETUP_TZ:-UTC}"
    timedatectl set-timezone "$tz" 2>/dev/null || true
    locale-gen en_US.UTF-8 >/dev/null 2>&1 || true
    update-locale LANG=en_US.UTF-8 >/dev/null 2>&1 || true
    systemctl enable --now chrony >/dev/null 2>&1 || true
    mark_done "timezone"
    ok "Timezone set to ${tz}, locale en_US.UTF-8, NTP sync (chrony) enabled"
  fi

  header "Swap Configuration"
  configure_swap

  header "Kernel & Network Performance Tuning"
  configure_sysctl

  header "File Descriptor & Journald Limits"
  configure_limits

  append_info_doc <<'EOF'

== [01] System Init ==
- apt update/upgrade run, base CLI toolchain installed (git, curl, build-essential, etc).
- Timezone set, en_US.UTF-8 locale generated, chrony NTP sync enabled (accurate clocks
  matter for TLS, JWT, and cron-scheduled jobs across every panel installed below).
- Swapfile sized to RAM (see /etc/fstab) with vm.swappiness=10 so the kernel prefers RAM
  but won't OOM-kill Coolify/x-ui containers under memory pressure.
- TCP BBR congestion control + larger socket/backlog buffers enabled for noticeably
  faster page loads and uploads, especially over higher-latency connections.
- journald log size capped at 200M so verbose container/service logs cannot fill the disk.
EOF

  mark_done "init"
  ok "Step 1/5 complete: base system initialized"
}

configure_swap() {
  if swapon --show | grep -q .; then
    ok "Swap already configured, skipping"
    return
  fi
  local mem_mb swap_mb
  mem_mb=$(awk '/MemTotal/{printf "%d", $2/1024}' /proc/meminfo)
  if   [ "$mem_mb" -le 2048 ]; then swap_mb=$((mem_mb * 2))
  elif [ "$mem_mb" -le 8192 ]; then swap_mb=$mem_mb
  else swap_mb=4096
  fi
  info "Creating ${swap_mb}MB swapfile at /swapfile..."
  fallocate -l "${swap_mb}M" /swapfile || dd if=/dev/zero of=/swapfile bs=1M count="$swap_mb" status=none
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  ok "Swapfile (${swap_mb}MB) created and enabled"
}

configure_sysctl() {
  local conf=/etc/sysctl.d/99-svsetup.conf
  cat > "$conf" <<'EOF'
# Managed by svsetup — performance & sane defaults for a Docker/Coolify host.
vm.swappiness = 10
vm.vfs_cache_pressure = 50
vm.overcommit_memory = 1
fs.file-max = 2097152
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 16384
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_fastopen = 3
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
  modprobe tcp_bbr 2>/dev/null || true
  sysctl --system >/dev/null 2>&1 || true
  ok "sysctl tuning applied (BBR congestion control, larger backlogs, swappiness=10)"
}

configure_limits() {
  cat > /etc/security/limits.d/99-svsetup.conf <<'EOF'
*    soft nofile 1048576
*    hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
EOF
  mkdir -p /etc/systemd/journald.conf.d
  cat > /etc/systemd/journald.conf.d/99-svsetup.conf <<'EOF'
[Journal]
SystemMaxUse=200M
MaxRetentionSec=2week
EOF
  systemctl restart systemd-journald >/dev/null 2>&1 || true
  ok "Open-file limits raised to 1,048,576; journald capped at 200M"
}

# Allow running standalone: bash modules/01-init.sh
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  require_root; require_ubuntu
  module_init
fi
