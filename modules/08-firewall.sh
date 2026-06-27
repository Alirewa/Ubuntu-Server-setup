#!/usr/bin/env bash
# 08-firewall.sh — dedicated firewall management: list / add / remove rules.
# Thin wrapper around UFW so port changes don't require remembering ufw syntax.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

module_firewall() {
  command -v ufw >/dev/null 2>&1 || { pkg_install ufw; }
  while true; do
    clear
    header "Firewall Management (UFW)"
    ufw status numbered || true
    echo
    echo "  1) Allow a port"
    echo "  2) Remove a rule by number (shown above)"
    echo "  3) Remove a rule by port"
    echo "  4) Show detailed status"
    echo "  0) Back to main menu"
    echo
    local c
    ask c "Choose" "0"
    case "$c" in
      1) fw_add_port ;;
      2) fw_remove_by_number ;;
      3) fw_remove_by_port ;;
      4) ufw status verbose; press_enter ;;
      0) return 0 ;;
      *) warn "Invalid choice" ;;
    esac
  done
}

fw_add_port() {
  local port proto label
  ask port "Port or range to allow (e.g. 9000 or 9000:9010)" ""
  if [ -z "$port" ]; then warn "No port entered"; return; fi
  ask proto "Protocol (tcp/udp/both)" "tcp"
  ask label "Label/comment for this rule" "manual"
  case "$proto" in
    both) ufw_allow "${port}/tcp" "$label"; ufw_allow "${port}/udp" "$label" ;;
    udp)  ufw_allow "${port}/udp" "$label" ;;
    *)    ufw_allow "${port}/tcp" "$label" ;;
  esac
  ok "Rule added for ${port} (${proto})"
  press_enter
}

fw_remove_by_number() {
  ufw status numbered || true
  local num
  ask num "Rule number to delete (blank to cancel)" ""
  [ -z "$num" ] && return
  yes | ufw delete "$num" >/dev/null 2>&1 || warn "Failed to delete rule #${num} (it may not exist)"
  ok "Rule #${num} removed (if it existed)"
  press_enter
}

fw_remove_by_port() {
  local port
  ask port "Port to remove, optionally with /tcp or /udp (e.g. 9000 or 9000/udp)" ""
  [ -z "$port" ] && return
  ufw delete allow "$port" >/dev/null 2>&1 || warn "No matching allow-rule found for ${port}"
  ok "Removed allow-rule for ${port} (if it existed)"
  press_enter
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  require_root; require_ubuntu
  module_firewall
fi
