#!/usr/bin/env bash
# 10-reset.sh — one question, then a full unconditional teardown of everything
# svsetup ever installed: Coolify (and its app data), 3x-ui, Telegram bots,
# Docker, firewall/SSH hardening, sysctl/swap tuning, extra packages, the
# domain registry, and svsetup itself — leaving the server as if it had never
# been run. No OS reinstall is ever required for this.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

module_reset() {
  header "Reset — return this server to its pre-svsetup state"
  warn "This permanently removes EVERYTHING svsetup installed: Coolify (including every"
  warn "app/database/backup it manages), 3x-ui, Telegram bots, Docker, firewall rules,"
  warn "SSH/security hardening, performance tuning, extra packages, the domain registry,"
  warn "and svsetup itself. This cannot be undone, and there is nothing to confirm after"
  warn "this one question — it runs straight through."
  echo
  confirm "Wipe everything svsetup installed and return this server to its initial state?" "N" || return 0

  reset_bots
  reset_xui
  reset_coolify
  reset_docker
  reset_security
  reset_performance
  reset_extras
  rm -f "${SVSETUP_STATE_DIR}/domains.tsv"

  rm -f /usr/local/bin/svsetup
  rm -rf "$SVSETUP_DIR" "$SVSETUP_LOG_DIR" "$SVSETUP_INFO_FILE"
  ok "Done. This server is back to its pre-svsetup state."
  info "To start over: curl -fsSL https://raw.githubusercontent.com/Alirewa/Ubuntu-Server-setup/main/install.sh -o svsetup-install.sh && sudo bash svsetup-install.sh"
  exit 0
}

reset_bots() {
  header "Telegram bots"
  local found=0
  if systemctl list-unit-files 2>/dev/null | grep -q '^tg-bot-auto-sender' || [ -d /opt/tg-bot-auto-sender ]; then
    found=1
    systemctl disable --now tg-bot-auto-sender >/dev/null 2>&1 || true
    rm -f /etc/systemd/system/tg-bot-auto-sender.service
    rm -rf /opt/tg-bot-auto-sender
    rm -f /usr/local/bin/tgsender
    ok "tg-bot-auto-sender removed"
  fi
  if systemctl list-unit-files 2>/dev/null | grep -q '^gdrive-uploader' || [ -d /opt/gdrive-uploader-bot ]; then
    found=1
    systemctl disable --now gdrive-uploader >/dev/null 2>&1 || true
    rm -f /etc/systemd/system/gdrive-uploader.service
    docker rm -f gdrive-bot-api >/dev/null 2>&1 || true
    rm -rf /opt/gdrive-uploader-bot
    rm -f /usr/local/bin/tgdrive
    ok "tg-bot-uploader-drive removed"
  fi
  systemctl daemon-reload >/dev/null 2>&1 || true
  rm -f "${SVSETUP_STATE_DIR}/bots.done"
  [ "$found" = 0 ] && info "No bots were installed — nothing to do."
}

reset_xui() {
  header "3x-ui"
  local found=0

  if [ -d /opt/3x-ui ] || docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q '^3xui_app$'; then
    found=1
    [ -f /opt/3x-ui/docker-compose.yml ] && ( cd /opt/3x-ui && docker compose down --rmi local --volumes >/dev/null 2>&1 || true )
    docker rm -f 3xui_app >/dev/null 2>&1 || true
    rm -rf /opt/3x-ui
    rm -f /usr/local/bin/x-ui
    ok "Docker-based 3x-ui removed (including the 'x-ui' host shim)"
  fi

  # Legacy (pre-Docker, native systemd) install, in case this server still has one.
  if [ -d /usr/local/x-ui ] || [ -f /etc/systemd/system/x-ui.service ]; then
    found=1
    systemctl disable --now x-ui >/dev/null 2>&1 || true
    rm -rf /usr/local/x-ui /etc/x-ui /var/log/x-ui
    rm -f /etc/systemd/system/x-ui.service
    rm -rf /etc/systemd/system/x-ui.service.d
    rm -f /usr/bin/x-ui /usr/local/bin/x-ui
    systemctl daemon-reload >/dev/null 2>&1 || true
    ok "Legacy native 3x-ui removed"
  fi

  rm -f "${SVSETUP_STATE_DIR}/xui.done"
  [ "$found" = 0 ] && info "3x-ui is not installed — nothing to do."
}

reset_coolify() {
  header "Coolify"
  if [ ! -d /data/coolify ] && ! docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q '^coolify$'; then
    info "Coolify is not installed — nothing to do."
    return 0
  fi
  if [ -f /data/coolify/source/docker-compose.yml ]; then
    docker compose \
      -f /data/coolify/source/docker-compose.yml \
      -f /data/coolify/source/docker-compose.prod.yml \
      --env-file /data/coolify/source/.env \
      -p coolify down --volumes --remove-orphans >/dev/null 2>&1 || true
  fi
  # Fallback in case the compose teardown above couldn't run (e.g. a missing
  # .env): catch any remaining container/volume/network Coolify created by name.
  local leftovers; leftovers="$(docker ps -aq --filter 'name=coolify' 2>/dev/null)" || true
  [ -n "$leftovers" ] && docker rm -f $leftovers >/dev/null 2>&1 || true
  docker volume rm coolify-db >/dev/null 2>&1 || true
  docker network rm coolify >/dev/null 2>&1 || true
  rm -rf /data/coolify

  # The installer adds its own deploy key to authorized_keys, tagged with a
  # trailing "coolify" comment (it removes old entries the same way before
  # re-adding one — see its own `sed -i "/coolify/d"` step), so this is the
  # exact, installer-defined way to identify and remove just that one line.
  for home in /root /home/*; do
    [ -f "${home}/.ssh/authorized_keys" ] || continue
    sed -i '/coolify$/d' "${home}/.ssh/authorized_keys"
  done

  rm -f "${SVSETUP_STATE_DIR}/coolify.done"
  ok "Coolify, all its data, and its SSH deploy key have been removed"
}

reset_docker() {
  header "Docker Engine"
  command -v docker >/dev/null 2>&1 || { info "Docker is not installed — nothing to do."; return 0; }
  systemctl stop docker >/dev/null 2>&1 || true
  DEBIAN_FRONTEND=noninteractive apt-get purge -y -qq \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1 || true
  rm -rf /var/lib/docker /var/lib/containerd /etc/docker
  rm -f /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.asc
  apt-get update -qq || true
  rm -f "${SVSETUP_STATE_DIR}/docker.done"
  ok "Docker Engine purged"
}

reset_security() {
  header "Firewall & SSH hardening"
  if command -v ufw >/dev/null 2>&1; then
    yes | ufw reset >/dev/null 2>&1 || true
    ufw disable >/dev/null 2>&1 || true
    ok "UFW reset to defaults and disabled"
  fi
  if [ -f /etc/fail2ban/jail.d/svsetup-sshd.conf ]; then
    rm -f /etc/fail2ban/jail.d/svsetup-sshd.conf
    systemctl restart fail2ban >/dev/null 2>&1 || true
    ok "Removed svsetup's fail2ban jail"
  fi
  if [ -f /etc/ssh/sshd_config.d/99-svsetup.conf ]; then
    rm -f /etc/ssh/sshd_config.d/99-svsetup.conf
    sshd -t 2>/dev/null && { systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true; }
    ok "SSH hardening reverted — root login over SSH is allowed again (as it was before svsetup)"
  fi
  rm -f /etc/apt/apt.conf.d/52svsetup-unattended /etc/apt/apt.conf.d/20auto-upgrades
  rm -f "${SVSETUP_STATE_DIR}/security.done"
  ok "Security settings reverted"
}

reset_performance() {
  header "Performance tuning (sysctl / limits / swap / BuildKit)"
  rm -f /etc/sysctl.d/99-svsetup.conf \
        /etc/security/limits.d/99-svsetup.conf \
        /etc/systemd/journald.conf.d/99-svsetup.conf
  sysctl --system >/dev/null 2>&1 || true
  systemctl restart systemd-journald >/dev/null 2>&1 || true
  sed -i '/^DOCKER_BUILDKIT=1$/d' /etc/environment 2>/dev/null || true
  command -v docker >/dev/null 2>&1 && docker volume rm svsetup_buildkit_cache >/dev/null 2>&1 || true
  ok "sysctl/limits/journald/BuildKit tuning reverted to Ubuntu defaults"

  if swapon --show 2>/dev/null | grep -q '/swapfile'; then
    swapoff /swapfile 2>/dev/null || true
    sed -i '\#^/swapfile none swap sw 0 0$#d' /etc/fstab
    rm -f /swapfile
    ok "Swapfile removed"
  fi
  rm -f "${SVSETUP_STATE_DIR}/init.done" "${SVSETUP_STATE_DIR}/timezone.done" "${SVSETUP_STATE_DIR}/speed.done"
}

reset_extras() {
  header "Extra CLI packages"
  is_done "extras" || { info "Extra packages were not installed — nothing to do."; return 0; }
  DEBIAN_FRONTEND=noninteractive apt-get purge -y -qq \
    htop glances ncdu tmux fzf bat tree jq net-tools dnsutils rsync zstd >/dev/null 2>&1 || true
  rm -f /usr/local/bin/bat
  rm -f "${SVSETUP_STATE_DIR}/extras.done"
  ok "Extra packages removed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  require_root; require_ubuntu
  module_reset
fi
