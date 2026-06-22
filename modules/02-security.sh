#!/usr/bin/env bash
# 02-security.sh — Firewall, brute-force protection, SSH hardening (medium profile),
# unattended security updates. Designed to never lock you out of SSH by default.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

module_security() {
  header "Firewall (UFW)"
  setup_ufw

  header "Fail2ban (SSH brute-force protection)"
  setup_fail2ban

  header "SSH Hardening (medium profile)"
  setup_ssh

  header "Unattended Security Updates"
  setup_unattended_upgrades

  header "Misc Hardening"
  setup_misc

  append_info_doc <<'EOF'

== [02] Security ==
- UFW enabled: default-deny incoming, default-allow outgoing. Only ports explicitly
  opened by svsetup modules (SSH, and later Coolify/x-ui ports) are reachable.
- Fail2ban watches sshd and bans IPs after repeated failed logins (default jail).
- SSH hardened at a SAFE/medium level: root login over SSH disabled
  (PermitRootLogin no), empty passwords disabled, max auth tries lowered.
  Your SSH port and password authentication were left UNCHANGED so this step
  cannot lock you out. Run `svsetup --ssh-strict` later if you want to switch to a
  custom port + key-only auth once you've confirmed key-based login works.
- unattended-upgrades installed: Ubuntu security patches are applied automatically.
EOF

  mark_done "security"
  ok "Step 2/5 complete: security baseline applied"
}

setup_ufw() {
  pkg_install ufw
  local ssh_port
  ssh_port="$(ss -tlnp 2>/dev/null | grep -oP 'sshd.*?:\K[0-9]+' | head -1)"
  ssh_port="${ssh_port:-22}"
  ufw default deny incoming >/dev/null
  ufw default allow outgoing >/dev/null
  ufw_allow "${ssh_port}/tcp" "SSH"
  yes | ufw enable >/dev/null
  ok "UFW enabled (default deny incoming). SSH port ${ssh_port} allowed."
}

setup_fail2ban() {
  pkg_install fail2ban
  cat > /etc/fail2ban/jail.d/svsetup-sshd.conf <<'EOF'
[sshd]
enabled = true
backend = systemd
bantime = 1h
findtime = 10m
maxretry = 5
EOF
  systemctl enable --now fail2ban >/dev/null 2>&1
  ok "Fail2ban active: 5 failed SSH attempts in 10min -> 1h ban"
}

setup_ssh() {
  local sshd_conf=/etc/ssh/sshd_config.d/99-svsetup.conf
  cat > "$sshd_conf" <<'EOF'
# Managed by svsetup — medium-risk hardening profile.
# Port and PasswordAuthentication intentionally left untouched here.
PermitRootLogin no
PermitEmptyPasswords no
MaxAuthTries 4
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
EOF
  sshd -t && systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
  ok "SSH hardened (root login disabled). Port/password-auth unchanged for safety."
  warn "Optional stricter profile (custom port + key-only auth) available via: svsetup --ssh-strict"
}

# Optional, explicit opt-in — never run automatically.
ssh_strict_profile() {
  require_root
  warn "This changes your SSH port and disables password authentication."
  warn "Make sure you can already log in with an SSH key before continuing!"
  confirm "Have you confirmed key-based SSH login works for this server?" "N" || \
    die "Aborted. Set up an SSH key first: ssh-copy-id user@server"

  local new_port
  ask new_port "New SSH port (1024-65535)" "2222"
  local sshd_conf=/etc/ssh/sshd_config.d/99-svsetup.conf
  {
    echo "Port ${new_port}"
    echo "PasswordAuthentication no"
    echo "KbdInteractiveAuthentication no"
  } >> "$sshd_conf"
  ufw_allow "${new_port}/tcp" "SSH (strict profile)"
  sshd -t || die "sshd config invalid, aborting before reload"
  systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null
  ok "SSH now listens on port ${new_port}, password auth disabled."
  warn "Update your SSH client config / firewall allow-list before closing this session!"
}

setup_unattended_upgrades() {
  pkg_install unattended-upgrades apt-listchanges
  cat > /etc/apt/apt.conf.d/52svsetup-unattended <<'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF
  echo 'APT::Periodic::Update-Package-Lists "1";' > /etc/apt/apt.conf.d/20auto-upgrades
  echo 'APT::Periodic::Unattended-Upgrade "1";' >> /etc/apt/apt.conf.d/20auto-upgrades
  systemctl enable --now unattended-upgrades >/dev/null 2>&1
  ok "Unattended security upgrades enabled (no auto-reboot, by design)"
}

setup_misc() {
  # Disable uncommon/legacy services that add attack surface if present.
  for svc in avahi-daemon cups rpcbind; do
    systemctl disable --now "$svc" >/dev/null 2>&1 || true
  done
  ok "Disabled unused legacy services (avahi/cups/rpcbind) where present"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  require_root; require_ubuntu
  case "${1:-}" in
    --ssh-strict) ssh_strict_profile ;;
    *) module_security ;;
  esac
fi
