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
- SSH hardened at a SAFE/medium level: empty passwords disabled, max auth tries
  lowered, SSH port and password authentication left UNCHANGED. Root login over SSH
  (PermitRootLogin no) is ONLY disabled if a non-root sudo user with an SSH key
  already exists as a fallback — otherwise it's deliberately left enabled, because
  disabling it with no other way in would permanently lock you out. If you saw a
  prompt offering to create a sudo admin user, that's what this check was for.
  Run `svsetup --ssh-strict` later if you want to switch to a custom port + key-only
  auth once you've confirmed key-based login works.
- unattended-upgrades installed: Ubuntu security patches are applied automatically.
EOF

  mark_done "security"
  ok "Step 2/5 complete: security baseline applied"
}

setup_ufw() {
  pkg_install ufw
  local ssh_port
  ssh_port="$(detect_ssh_port)"
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
  local base_rules='PermitEmptyPasswords no
MaxAuthTries 4
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2'

  if has_alternate_admin_access; then
    printf '%s\n' "# Managed by svsetup — medium-risk hardening profile." \
                  "# Port and PasswordAuthentication intentionally left untouched here." \
                  "PermitRootLogin no" "$base_rules" > "$sshd_conf"
    ok "SSH hardened (root login disabled — a sudo user with an SSH key was found as a fallback)."
  elif confirm "No other sudo user with an SSH key was found. Create one now so root login can be safely disabled?" "Y"; then
    create_admin_user
    printf '%s\n' "# Managed by svsetup — medium-risk hardening profile." \
                  "# Port and PasswordAuthentication intentionally left untouched here." \
                  "PermitRootLogin no" "$base_rules" > "$sshd_conf"
    ok "SSH hardened (root login disabled, new sudo user is your fallback)."
  else
    printf '%s\n' "# Managed by svsetup — medium-risk hardening profile." \
                  "# PermitRootLogin intentionally NOT changed: no alternate sudo/SSH-key user" \
                  "# exists, and disabling it here would permanently lock you out." \
                  "$base_rules" > "$sshd_conf"
    warn "Root login over SSH was left ENABLED — disabling it with no fallback admin user"
    warn "would have locked you out permanently (this happened to real users before this fix)."
    warn "Create a sudo user with an SSH key, then re-run this step to harden root login."
  fi

  sshd -t && systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
  warn "Optional stricter profile (custom port + key-only auth) available via: svsetup --ssh-strict"
}

# has_alternate_admin_access — true if a non-root user in the `sudo` group has at
# least one SSH key already authorized. Disabling PermitRootLogin is only safe
# when this is true; otherwise root would be the only way in and SSH would lock
# out completely the moment root login is refused.
has_alternate_admin_access() {
  local members u home
  members="$(getent group sudo 2>/dev/null | cut -d: -f4)" || true
  IFS=',' read -ra members <<< "$members"
  for u in "${members[@]}"; do
    [ -z "$u" ] && continue
    home="$(getent passwd "$u" 2>/dev/null | cut -d: -f6)" || true
    [ -n "$home" ] && [ -s "${home}/.ssh/authorized_keys" ] && return 0
  done
  return 1
}

# create_admin_user — interactively create a sudo user and give it an SSH key,
# either by copying root's existing authorized_keys (the safe non-interactive
# default on a fresh VPS) or a key the operator pastes in.
create_admin_user() {
  local username
  ask username "Username for the new sudo admin user" "admin"
  if ! id "$username" >/dev/null 2>&1; then
    adduser --disabled-password --gecos "" "$username"
  fi
  usermod -aG sudo "$username"
  local home="/home/${username}"
  mkdir -p "${home}/.ssh"
  if [ -s /root/.ssh/authorized_keys ] && confirm "Copy root's current SSH key(s) to ${username} (recommended)?" "Y"; then
    cp /root/.ssh/authorized_keys "${home}/.ssh/authorized_keys"
  else
    local pubkey
    ask pubkey "Paste a public SSH key for ${username} (blank to skip)" ""
    [ -n "$pubkey" ] && echo "$pubkey" >> "${home}/.ssh/authorized_keys"
  fi
  chmod 700 "${home}/.ssh"
  chmod 600 "${home}/.ssh/authorized_keys" 2>/dev/null || true
  chown -R "${username}:${username}" "${home}/.ssh"
  ok "Sudo user '${username}' created. Test logging in as ${username} in a NEW terminal before closing this session."
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
