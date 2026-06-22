#!/usr/bin/env bash
# common.sh — shared helpers sourced by every module in svsetup.
# Not meant to be executed directly.

SVSETUP_DIR="${SVSETUP_DIR:-/opt/svsetup}"
SVSETUP_STATE_DIR="${SVSETUP_DIR}/.state"
SVSETUP_LOG_DIR="/var/log/svsetup"
SVSETUP_LOG_FILE="${SVSETUP_LOG_DIR}/svsetup.log"
SVSETUP_INFO_FILE="/root/svsetup-README.txt"

mkdir -p "$SVSETUP_STATE_DIR" "$SVSETUP_LOG_DIR" 2>/dev/null || true
touch "$SVSETUP_INFO_FILE" 2>/dev/null || true

if [ -t 1 ]; then
  C_RED=$'\033[0;31m'; C_GREEN=$'\033[0;32m'; C_YELLOW=$'\033[1;33m'
  C_CYAN=$'\033[0;36m'; C_BOLD=$'\033[1m'; C_RESET=$'\033[0m'
else
  C_RED=''; C_GREEN=''; C_YELLOW=''; C_CYAN=''; C_BOLD=''; C_RESET=''
fi

log()   { printf '%s\n' "$*" | tee -a "$SVSETUP_LOG_FILE" >/dev/null; }
info()  { printf '%s\n' "${C_CYAN}[INFO]${C_RESET}  $*"; log "[INFO] $*"; }
ok()    { printf '%s\n' "${C_GREEN}[OK]${C_RESET}    $*"; log "[OK] $*"; }
warn()  { printf '%s\n' "${C_YELLOW}[WARN]${C_RESET}  $*"; log "[WARN] $*"; }
err()   { printf '%s\n' "${C_RED}[ERROR]${C_RESET} $*" >&2; log "[ERROR] $*"; }
die()   { err "$*"; exit 1; }
header(){ printf '\n%s\n' "${C_BOLD}${C_CYAN}== $* ==${C_RESET}"; log "== $* =="; }

require_root() {
  [ "$(id -u)" -eq 0 ] || die "This script must be run as root (use: sudo svsetup)."
}

require_ubuntu() {
  [ -f /etc/os-release ] || die "Cannot detect OS. Ubuntu 22.04/24.04 required."
  . /etc/os-release
  [ "${ID:-}" = "ubuntu" ] || die "This toolkit only supports Ubuntu. Detected: ${ID:-unknown}."
  local major="${VERSION_ID%%.*}"
  [ "${major:-0}" -ge 22 ] || die "Ubuntu 22.04+ required. Detected: ${VERSION_ID:-unknown}."
}

# confirm "Question" [default: Y/N] -> returns 0 for yes
confirm() {
  local prompt="$1" default="${2:-Y}" ans
  local hint="[Y/n]"; [ "$default" = "N" ] && hint="[y/N]"
  read -r -p "$(printf '%s' "${C_BOLD}${prompt} ${hint}: ${C_RESET}")" ans </dev/tty || ans=""
  ans="${ans:-$default}"
  [[ "$ans" =~ ^[Yy] ]]
}

# ask VAR "Prompt" "default"
ask() {
  local __var="$1" prompt="$2" default="${3:-}" hint val
  hint=""; [ -n "$default" ] && hint=" [${default}]"
  read -r -p "$(printf '%s' "${C_BOLD}${prompt}${hint}: ${C_RESET}")" val </dev/tty || val=""
  printf -v "$__var" '%s' "${val:-$default}"
}

is_done()   { [ -f "${SVSETUP_STATE_DIR}/$1.done" ]; }
mark_done() { echo "$(date -Iseconds)" > "${SVSETUP_STATE_DIR}/$1.done"; }

pkg_install() {
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"
}

apt_update_once() {
  if [ ! -f "${SVSETUP_STATE_DIR}/.apt_updated_today" ] || \
     [ "$(find "${SVSETUP_STATE_DIR}/.apt_updated_today" -mmin +60 2>/dev/null)" ]; then
    info "Refreshing apt package lists..."
    DEBIAN_FRONTEND=noninteractive apt-get update -qq
    touch "${SVSETUP_STATE_DIR}/.apt_updated_today"
  fi
}

ufw_allow() {
  command -v ufw >/dev/null 2>&1 || return 0
  ufw allow "$1" comment "${2:-svsetup}" >/dev/null
}

# Run a remote installer script safely: download first, then execute,
# so the script's own stdin reads (interactive prompts) are not eaten
# by the curl pipe.
run_remote_installer() {
  local url="$1"; shift
  local tmp; tmp="$(mktemp /tmp/svsetup-installer-XXXXXX.sh)"
  curl -fsSL "$url" -o "$tmp" || die "Failed to download installer: $url"
  chmod +x "$tmp"
  bash "$tmp" "$@"
  local rc=$?
  rm -f "$tmp"
  return $rc
}

append_info_doc() {
  cat >> "$SVSETUP_INFO_FILE"
}

press_enter() {
  read -r -p "Press Enter to continue..." _ </dev/tty || true
}
