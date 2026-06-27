#!/usr/bin/env bash
# svsetup — interactive control panel for Ubuntu-Server-setup.
# Re-run any time: `sudo svsetup`. Every module is idempotent/safe to repeat.
set -euo pipefail
SVSETUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SVSETUP_DIR}/lib/common.sh"

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

run_initial_setup() {
  module_init
  module_security
  module_docker
}

coolify_with_deps() {
  is_done "docker" || module_docker
  module_coolify
}

show_status() {
  header "Installed Components"
  for s in init security docker coolify xui bots extras speed; do
    if is_done "$s"; then ok "$s"; else warn "$s — not installed yet"; fi
  done
  echo
  info "Full doc / per-component notes: ${SVSETUP_INFO_FILE}"
  info "Logs: ${SVSETUP_LOG_FILE}"
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
  echo "  4) Telegram bots"
  echo "  5) Extra packages"
  echo "  6) Firewall"
  echo "  7) Speed boost"
  echo "  8) Self-update"
  echo "  9) Status"
  echo " 10) Reset / uninstall"
  echo " 11) Docker containers"
  echo " 12) Edit config files"
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
      3) run_step "3x-ui setup" module_xui ;;
      4) run_step "Telegram bots" module_bots ;;
      5) run_step "Extra packages" module_extras ;;
      6) module_firewall ;;
      7) run_step "Speed boost" module_speed ;;
      8) update_self ;;
      9) show_status ;;
      10) module_reset; press_enter ;;
      11) module_docker_manage ;;
      12) module_edit_files ;;
      0) exit 0 ;;
      *) warn "Invalid choice" ;;
    esac
  done
}

usage() {
  cat <<EOF
Usage: svsetup [--init|--coolify|--xui|--bots|--extras|--firewall|--speed|--update|--reset|--docker|--edit|--all|--ssh-strict]
No flags: opens the interactive menu.
EOF
}

require_root
require_ubuntu

case "${1:-}" in
  --init)       run_initial_setup ;;
  --coolify)    is_done "docker" || module_docker; module_coolify ;;
  --xui)        module_xui ;;
  --bots)       module_bots ;;
  --extras)     module_extras ;;
  --firewall)   module_firewall ;;
  --speed)      module_speed ;;
  --update)     update_self ;;
  --reset)      module_reset ;;
  --docker)     module_docker_manage ;;
  --edit)       module_edit_files ;;
  --ssh-strict) ssh_strict_profile ;;
  --all)        run_initial_setup; module_coolify; module_xui; module_extras ;;
  -h|--help)    usage ;;
  "")           main_menu ;;
  *)            usage; exit 1 ;;
esac
