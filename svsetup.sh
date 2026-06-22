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

run_initial_setup() {
  module_init
  module_security
  module_docker
}

show_status() {
  header "Installed Components"
  for s in init security docker coolify xui bots extras; do
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
  echo "  1) Initial server setup   (update + security + Docker)"
  echo "  2) Install / update Coolify          (deploy panel)"
  echo "  3) Install / update 3x-ui             (Sanaei VPN panel)"
  echo "  4) Telegram bots                      (auto-sender / drive-uploader)"
  echo "  5) Install extra useful packages"
  echo "  6) Show installed components / docs"
  echo "  0) Exit"
  echo
}

main_menu() {
  while true; do
    print_menu
    local choice
    ask choice "Choose an option" "0"
    case "$choice" in
      1) run_initial_setup; press_enter ;;
      2) require_root; require_ubuntu
         is_done "docker" || module_docker
         module_coolify; press_enter ;;
      3) module_xui; press_enter ;;
      4) module_bots; press_enter ;;
      5) module_extras; press_enter ;;
      6) show_status ;;
      0) exit 0 ;;
      *) warn "Invalid choice" ;;
    esac
  done
}

usage() {
  cat <<EOF
Usage: svsetup [--init|--coolify|--xui|--bots|--extras|--all|--ssh-strict]
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
  --ssh-strict) ssh_strict_profile ;;
  --all)        run_initial_setup; module_coolify; module_xui; module_extras ;;
  -h|--help)    usage ;;
  "")           main_menu ;;
  *)            usage; exit 1 ;;
esac
