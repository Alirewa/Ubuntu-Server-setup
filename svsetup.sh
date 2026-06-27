#!/usr/bin/env bash
# svsetup — interactive control panel for Ubuntu-Server-setup.
# Re-run any time: `sudo svsetup`. Every module is idempotent/safe to repeat,
# in any order — see lib/common.sh's ensure_docker() and is_done()/mark_done().
set -euo pipefail
# Resolve through the /usr/local/bin/svsetup symlink — BASH_SOURCE alone
# would resolve to /usr/local/bin (the symlink's own directory) instead of
# the real /opt/svsetup install, which is exactly why `svsetup` failed to
# find lib/common.sh when run via the symlink.
SVSETUP_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=lib/common.sh
source "${SVSETUP_DIR}/lib/common.sh"

# Single-instance lock: prevents two svsetup runs (e.g. two SSH sessions)
# from writing the same files — sysctl conf, ufw rules, daemon.json, state
# markers — at the same time and corrupting each other's changes.
SVSETUP_LOCK_FILE="${SVSETUP_STATE_DIR}/svsetup.lock"
exec 9>"$SVSETUP_LOCK_FILE"
if ! flock -n 9; then
  echo "Another svsetup process is already running on this server." >&2
  echo "Wait for it to finish, then try again. (Lock: ${SVSETUP_LOCK_FILE})" >&2
  exit 1
fi

# Full transcript logging: every line this script and the commands it runs
# print (not just the curated info/ok/warn/err lines) is appended to the log,
# so a failure can be debugged after the fact without having to reproduce it.
exec > >(tee -a "$SVSETUP_LOG_FILE") 2> >(tee -a "$SVSETUP_LOG_FILE" >&2)

# shellcheck source=modules/01-init.sh
source "${SVSETUP_DIR}/modules/01-init.sh"
# shellcheck source=modules/02-security.sh
source "${SVSETUP_DIR}/modules/02-security.sh"
# shellcheck source=modules/03-docker.sh
source "${SVSETUP_DIR}/modules/03-docker.sh"
# shellcheck source=modules/04-coolify.sh
source "${SVSETUP_DIR}/modules/04-coolify.sh"
# shellcheck source=modules/05-xui.sh
source "${SVSETUP_DIR}/modules/05-xui.sh"
# shellcheck source=modules/06-bots.sh
source "${SVSETUP_DIR}/modules/06-bots.sh"
# shellcheck source=modules/07-extras.sh
source "${SVSETUP_DIR}/modules/07-extras.sh"
# shellcheck source=modules/08-firewall.sh
source "${SVSETUP_DIR}/modules/08-firewall.sh"
# shellcheck source=modules/09-speed.sh
source "${SVSETUP_DIR}/modules/09-speed.sh"
# shellcheck source=modules/10-reset.sh
source "${SVSETUP_DIR}/modules/10-reset.sh"
# shellcheck source=modules/11-docker-manage.sh
source "${SVSETUP_DIR}/modules/11-docker-manage.sh"
# shellcheck source=modules/12-edit-files.sh
source "${SVSETUP_DIR}/modules/12-edit-files.sh"
# shellcheck source=modules/13-domains.sh
source "${SVSETUP_DIR}/modules/13-domains.sh"

run_initial_setup() {
  module_init
  module_security
  module_docker
}

coolify_with_deps() {
  ensure_docker
  module_coolify
}

show_status() {
  header "Installed Components"
  for s in init security docker coolify xui bots extras speed; do
    if is_done "$s"; then ok "$s"; else warn "$s — not installed yet"; fi
  done
  echo
  info "Full docs: ${SVSETUP_INFO_FILE}"
  info "Log file:  ${SVSETUP_LOG_FILE}  (full transcript of every run — start here when debugging)"
  if confirm "Show the last 30 log lines now?" "N"; then
    echo
    tail -n 30 "$SVSETUP_LOG_FILE" 2>/dev/null || warn "Log file is empty or not readable yet."
  fi
  press_enter
}

print_menu() {
  clear
  printf '%s\n' "${C_BOLD}${C_CYAN}==================================================${C_RESET}"
  printf '%s\n' "${C_BOLD}${C_CYAN}        SV-Setup — Ubuntu Server Control Panel     ${C_RESET}"
  printf '%s\n' "${C_BOLD}${C_CYAN}==================================================${C_RESET}"
  echo "  1) Initial setup     — update, security, Docker"
  echo "  2) Coolify           — deploy panel"
  echo "  3) 3x-ui             — VPN panel"
  echo "  4) Domains           — track/avoid conflicts, DNS check"
  echo "  5) Telegram bots"
  echo "  6) Extra packages"
  echo "  7) Firewall"
  echo "  8) Speed boost"
  echo "  9) Docker containers"
  echo " 10) Edit config files"
  echo " 11) Status / logs"
  echo " 12) Self-update"
  echo " 13) Reset / uninstall"
  echo "  0) Exit"
  echo
}

# run_step LABEL FUNC [ARGS...] — runs a module in a subshell so a failure
# (set -e / die() inside the module) can never kill the whole svsetup session;
# it just reports the error and returns you to the menu.
run_step() {
  local label="$1"; shift
  if ( "$@" ); then
    :
  else
    local rc=$?
    err "${label} failed (exit ${rc}). See ${SVSETUP_LOG_FILE} for details."
  fi
  press_enter
}

main_menu() {
  while true; do
    print_menu
    local choice
    ask choice "Choose an option" "0"
    case "$choice" in
      1) run_step "Initial server setup" run_initial_setup ;;
      2) run_step "Coolify setup" coolify_with_deps ;;
      3) module_xui ;;
      4) module_domains ;;
      5) run_step "Telegram bots" module_bots ;;
      6) run_step "Extra packages" module_extras ;;
      7) module_firewall ;;
      8) run_step "Speed boost" module_speed ;;
      9) module_docker_manage ;;
      10) module_edit_files ;;
      11) show_status ;;
      12) update_self ;;
      13) module_reset; press_enter ;;
      0) exit 0 ;;
      *) warn "Invalid choice" ;;
    esac
  done
}

usage() {
  cat <<EOF
Usage: svsetup [--init|--coolify|--xui|--domains|--bots|--extras|--firewall|--speed|--docker|--edit|--update|--reset|--all|--ssh-strict]
No flags: opens the interactive menu.
EOF
}

require_root
require_ubuntu

case "${1:-}" in
  --init)       run_initial_setup ;;
  --coolify)    coolify_with_deps ;;
  --xui)        xui_install_or_update ;;
  --domains)    module_domains ;;
  --bots)       module_bots ;;
  --extras)     module_extras ;;
  --firewall)   module_firewall ;;
  --speed)      module_speed ;;
  --docker)     module_docker_manage ;;
  --edit)       module_edit_files ;;
  --update)     update_self ;;
  --reset)      module_reset ;;
  --ssh-strict) ssh_strict_profile ;;
  --all)        run_initial_setup; module_coolify; xui_install_or_update; module_extras ;;
  -h|--help)    usage ;;
  "")           main_menu ;;
  *)            usage; exit 1 ;;
esac
