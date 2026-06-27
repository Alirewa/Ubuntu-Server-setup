#!/usr/bin/env bash
# 10-reset.sh — undo everything svsetup installed, component by component.
# No OS reinstall/server reset is ever required for this: everything svsetup
# changed was done via apt/docker/systemctl/ufw, and all of it is reversible
# the same way. Each destructive step is confirmed individually.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

module_reset() {
  header "Reset svsetup — undo everything this toolkit installed"
  warn "This walks through every component svsetup can install and offers to remove it."
  warn "You do NOT need to reinstall or reset the whole server for this — every change"
  warn "svsetup made was done with apt/docker/systemctl/ufw, and all of it can be undone"
  warn "the same way. A full OS reset is never required just to undo this script."
  echo
  confirm "Continue to the reset wizard?" "N" || return 0

  local phrase
  ask phrase "Type RESET (all caps) to confirm — some of the next steps permanently delete data" ""
  if [ "$phrase" != "RESET" ]; then
    warn "Confirmation text did not match — aborted, nothing was changed."
    return 0
  fi

  reset_bots
  reset_xui
  reset_coolify
  reset_docker
  reset_security
  reset_performance
  reset_extras

  echo
  if confirm "Also remove the svsetup toolkit itself (/opt/svsetup, the 'svsetup' command, logs)?" "N"; then
    rm -f /usr/local/bin/svsetup
    rm -rf "$SVSETUP_DIR" "$SVSETUP_LOG_DIR" "$SVSETUP_INFO_FILE"
    ok "svsetup toolkit removed."
    echo
    info "To start over later, run the one-line installer again:"
    info "curl -fsSL https://raw.githubusercontent.com/Alirewa/Ubuntu-Server-setup/main/install.sh -o svsetup-install.sh && sudo bash svsetup-install.sh"
    exit 0
  fi

  ok "Reset finished. Re-run any menu option any time (e.g. option 1) to start fresh."
}

reset_bots() {
  header "Telegram bots"
  local found=0
  if systemctl list-unit-files 2>/dev/null | grep -q '^tg-bot-auto-sender' || [ -d /opt/tg-bot-auto-sender ]; then
    found=1
    if confirm "Remove tg-bot-auto-sender (service + /opt/tg-bot-auto-sender)?" "Y"; then
      systemctl disable --now tg-bot-auto-sender >/dev/null 2>&1 || true
      rm -f /etc/systemd/system/tg-bot-auto-sender.service
      rm -rf /opt/tg-bot-auto-sender
      rm -f /usr/local/bin/tgsender
      ok "tg-bot-auto-sender removed"
    fi
  fi
  if systemctl list-unit-files 2>/dev/null | grep -q '^gdrive-uploader' || [ -d /opt/gdrive-uploader-bot ]; then
    found=1
    if confirm "Remove tg-bot-uploader-drive (service + container + /opt/gdrive-uploader-bot)?" "Y"; then
      systemctl disable --now gdrive-uploader >/dev/null 2>&1 || true
      rm -f /etc/systemd/system/gdrive-uploader.service
      docker rm -f gdrive-bot-api >/dev/null 2>&1 || true
      rm -rf /opt/gdrive-uploader-bot
      rm -f /usr/local/bin/tgdrive
      ok "tg-bot-uploader-drive removed"
    fi
  fi
  systemctl daemon-reload >/dev/null 2>&1 || true
  rm -f "${SVSETUP_STATE_DIR}/bots.done"
  [ "$found" = 0 ] && info "No bots were installed — nothing to do."
}

reset_xui() {
  header "3x-ui"
  local found=0

  # Current (Docker-based) install.
  if [ -d /opt/3x-ui ] || docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q '^3xui_app$'; then
    found=1
    confirm "Remove the Docker-based 3x-ui (container + image + /opt/3x-ui, including its database)?" "N" && {
      [ -f /opt/3x-ui/docker-compose.yml ] && ( cd /opt/3x-ui && docker compose down --rmi local --volumes >/dev/null 2>&1 || true )
      docker rm -f 3xui_app >/dev/null 2>&1 || true
      rm -rf /opt/3x-ui
      rm -f /usr/local/bin/x-ui
      ok "Docker-based 3x-ui removed (including the 'x-ui' host shim)"
    }
  fi

  # Legacy (pre-Docker, native systemd) install, in case this server still has one.
  # Note: don't key this off `command -v x-ui` alone — the current Docker install
  # also provides an `x-ui` host command (a thin proxy), which would otherwise
  # always look like a leftover legacy install.
  if [ -d /usr/local/x-ui ] || [ -f /etc/systemd/system/x-ui.service ]; then
    found=1
    confirm "A legacy native (non-Docker) 3x-ui install was also found — remove it too?" "N" && {
      systemctl disable --now x-ui >/dev/null 2>&1 || true
      rm -rf /usr/local/x-ui /etc/x-ui /var/log/x-ui
      rm -f /etc/systemd/system/x-ui.service
      rm -rf /etc/systemd/system/x-ui.service.d
      rm -f /usr/bin/x-ui /usr/local/bin/x-ui
      systemctl daemon-reload >/dev/null 2>&1 || true
      ok "Legacy native 3x-ui removed"
    }
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
  warn "This permanently deletes Coolify AND every app/database/backup it manages, in /data/coolify."
  confirm "Remove Coolify and ALL its data? This cannot be undone." "N" || { warn "Skipped."; return 0; }
  if [ -f /data/coolify/source/docker-compose.yml ]; then
    docker compose \
      -f /data/coolify/source/docker-compose.yml \
      -f /data/coolify/source/docker-compose.prod.yml \
      --env-file /data/coolify/source/.env \
      -p coolify down --volumes --remove-orphans >/dev/null 2>&1 || true
  fi
  docker rm -f coolify >/dev/null 2>&1 || true
  docker volume rm coolify-db >/dev/null 2>&1 || true
  rm -rf /data/coolify
  rm -f "${SVSETUP_STATE_DIR}/coolify.done"
  ok "Coolify and its data removed"
  warn "Coolify also added an SSH key to ~/.ssh/authorized_keys (used for its local docker context)."
  warn "Review and remove that entry by hand if you want it fully clean."
}

reset_docker() {
  header "Docker Engine"
  command -v docker >/dev/null 2>&1 || { info "Docker is not installed — nothing to do."; return 0; }
  warn "This deletes ALL Docker containers, images, volumes and networks on this server,"
  warn "including anything left over from Coolify/x-ui/bots if you didn't remove them above."
  confirm "Purge Docker Engine completely?" "N" || { warn "Skipped."; return 0; }
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
    if confirm "Reset UFW to factory defaults (removes ALL rules — svsetup's and any you added — and disables it)?" "Y"; then
      yes | ufw reset >/dev/null 2>&1 || true
      ufw disable >/dev/null 2>&1 || true
      ok "UFW reset to defaults and disabled"
    fi
  fi
  if [ -f /etc/fail2ban/jail.d/svsetup-sshd.conf ]; then
    rm -f /etc/fail2ban/jail.d/svsetup-sshd.conf
    systemctl restart fail2ban >/dev/null 2>&1 || true
    ok "Removed svsetup's fail2ban jail"
  fi
  if [ -f /etc/ssh/sshd_config.d/99-svsetup.conf ]; then
    rm -f /etc/ssh/sshd_config.d/99-svsetup.conf
    sshd -t 2>/dev/null && { systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true; }
    warn "SSH hardening reverted — root login over SSH is allowed again (as it was before svsetup)."
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
    if confirm "Remove the swapfile svsetup created (/swapfile)? Keeping it is harmless." "N"; then
      swapoff /swapfile 2>/dev/null || true
      sed -i '\#^/swapfile none swap sw 0 0$#d' /etc/fstab
      rm -f /swapfile
      ok "Swapfile removed"
    fi
  fi
  rm -f "${SVSETUP_STATE_DIR}/init.done" "${SVSETUP_STATE_DIR}/timezone.done" "${SVSETUP_STATE_DIR}/speed.done"
}

reset_extras() {
  header "Extra CLI packages"
  is_done "extras" || { info "Extra packages were not installed — nothing to do."; return 0; }
  confirm "Remove the extra CLI packages svsetup installed (htop, glances, ncdu, tmux, fzf, bat, tree, jq, net-tools, dnsutils, rsync, zstd)?" "N" || { warn "Skipped."; return 0; }
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
