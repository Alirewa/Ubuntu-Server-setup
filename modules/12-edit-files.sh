#!/usr/bin/env bash
# 12-edit-files.sh — pick from a short list of security-relevant config files
# and open one in an editor. Backs up before editing; SSH/JSON/Compose files
# are validated after saving and auto-reverted if the edit is broken.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

EDIT_TARGETS=(
  "/etc/ssh/sshd_config.d/99-svsetup.conf|SSH hardening rules|ssh"
  "/etc/ssh/sshd_config|Main SSH daemon config|ssh"
  "/etc/fail2ban/jail.d/svsetup-sshd.conf|Fail2ban SSH jail|fail2ban"
  "/etc/sysctl.d/99-svsetup.conf|Kernel/network tuning|sysctl"
  "/etc/docker/daemon.json|Docker daemon config|json"
  "/opt/3x-ui/docker-compose.yml|3x-ui Docker Compose|compose"
  "/etc/security/limits.d/99-svsetup.conf|Open-file limits|none"
  "/etc/crontab|System crontab|none"
  "/etc/hosts|Hosts file|none"
)

module_edit_files() {
  command -v "${EDITOR:-nano}" >/dev/null 2>&1 || pkg_install nano

  while true; do
    clear
    header "Edit Important Files"
    info "Backs up before editing. SSH/Docker/Compose files are checked after saving"
    info "and rolled back automatically if the change is broken."
    echo

    local shown=() n=0 e path label validator
    for e in "${EDIT_TARGETS[@]}"; do
      IFS='|' read -r path label validator <<< "$e"
      [ -f "$path" ] || continue
      n=$((n + 1))
      shown+=("$e")
      printf '  %2d) %-26s %s\n' "$n" "$label" "$path"
    done
    echo "   0) Back to main menu"
    echo

    local choice
    ask choice "Edit which file" "0"
    [ "$choice" = "0" ] && return 0
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "$n" ]; then
      warn "Invalid choice"
      continue
    fi
    IFS='|' read -r path label validator <<< "${shown[$((choice - 1))]}"
    edit_one_file "$path" "$label" "$validator"
  done
}

edit_one_file() {
  local path="$1" label="$2" validator="$3"
  local backup="${path}.svsetup-bak-$(date +%s)"
  cp "$path" "$backup"

  "${EDITOR:-nano}" "$path" </dev/tty >/dev/tty 2>&1 || true

  if cmp -s "$path" "$backup"; then
    info "No changes made to ${label}."
    rm -f "$backup"
  elif validate_edit "$path" "$validator"; then
    ok "${label} saved (backup kept at ${backup})"
    reload_after_edit "$validator" "$path"
  else
    warn "${label} failed validation — restoring the previous version."
    cp "$backup" "$path"
  fi
  press_enter
}

validate_edit() {
  local path="$1" validator="$2"
  case "$validator" in
    ssh)
      if sshd -t 2>/dev/null; then return 0; else return 1; fi
      ;;
    json)
      if command -v python3 >/dev/null 2>&1; then
        if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$path" 2>/dev/null; then
          return 0
        else
          return 1
        fi
      fi
      return 0
      ;;
    compose)
      if command -v docker >/dev/null 2>&1; then
        if ( cd "$(dirname "$path")" && docker compose -f "$(basename "$path")" config -q ) 2>/dev/null; then
          return 0
        else
          return 1
        fi
      fi
      return 0
      ;;
    *)
      return 0
      ;;
  esac
}

reload_after_edit() {
  local validator="$1" path="$2"
  case "$validator" in
    ssh)
      systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
      ok "sshd reloaded"
      ;;
    fail2ban)
      systemctl restart fail2ban >/dev/null 2>&1 || true
      ok "fail2ban restarted"
      ;;
    sysctl)
      sysctl --system >/dev/null 2>&1 || true
      ok "sysctl reloaded"
      ;;
    json)
      warn "Apply with: systemctl restart docker (this restarts ALL containers — pick a safe time)"
      ;;
    compose)
      warn "Apply with: (cd $(dirname "$path") && docker compose up -d)"
      ;;
    *) : ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  require_root; require_ubuntu
  module_edit_files
fi
