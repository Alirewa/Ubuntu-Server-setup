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

# detect_ssh_port — never fails (every fallible step is explicitly guarded),
# safe to call under `set -euo pipefail`. Returns 22 if nothing else is found.
detect_ssh_port() {
  local p=""
  p="$(sshd -T 2>/dev/null | awk 'tolower($1)=="port"{print $2; exit}')" || true
  if [ -z "$p" ]; then
    p="$(grep -iE '^[[:space:]]*Port[[:space:]]+[0-9]+' /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -1)" || true
  fi
  printf '%s' "${p:-22}"
}

# ask_open_ports CONTEXT_LABEL — generic pre-install prompt so any project,
# known or not, can have its ports opened without svsetup hardcoding them.
ask_open_ports() {
  local context="$1" ports entry proto
  ask ports "Any extra ports ${context} needs open on the firewall? (e.g. 9000 or 9000:9010, comma-separated, blank = none)" ""
  [ -z "$ports" ] && return 0
  local IFS=','
  for entry in $ports; do
    entry="$(echo "$entry" | xargs)"
    [ -z "$entry" ] && continue
    ask proto "Protocol for ${entry} (tcp/udp/both)" "tcp"
    case "$proto" in
      both) ufw_allow "${entry}/tcp" "$context"; ufw_allow "${entry}/udp" "$context" ;;
      udp)  ufw_allow "${entry}/udp" "$context" ;;
      *)    ufw_allow "${entry}/tcp" "$context" ;;
    esac
    ok "Opened ${entry} (${proto}) for ${context}"
  done
}

# apply_network_tuning — BBR + sysctl/limits tuning shared by the initial
# setup and the standalone "speed boost" module. Idempotent.
apply_network_tuning() {
  local conf=/etc/sysctl.d/99-svsetup.conf
  cat > "$conf" <<'EOF'
# Managed by svsetup — performance & sane defaults for a Docker/Coolify host.
vm.swappiness = 10
vm.vfs_cache_pressure = 50
vm.overcommit_memory = 1
fs.file-max = 2097152
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 16384
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_fastopen = 3
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
  modprobe tcp_bbr 2>/dev/null || true
  sysctl --system >/dev/null 2>&1 || true
  ok "sysctl tuning applied (BBR congestion control, larger backlogs, swappiness=10)"
}

# ensure_docker — install Docker only if it's not actually present yet. Checks
# the real `docker` command, not the is_done("docker") marker, so this stays
# correct regardless of HOW Docker got installed (our module 03, or a bot's
# own installer running get.docker.com) and regardless of what order the menu
# options were run in. Safe to call from any module that needs Docker.
ensure_docker() {
  command -v docker >/dev/null 2>&1 || module_docker
}

# enable_buildkit_cache — shared by Coolify install and the speed module.
enable_buildkit_cache() {
  command -v docker >/dev/null 2>&1 || return 0
  docker volume create svsetup_buildkit_cache >/dev/null 2>&1 || true
  if ! grep -q DOCKER_BUILDKIT /etc/environment 2>/dev/null; then
    echo 'DOCKER_BUILDKIT=1' >> /etc/environment
  fi
  ok "BuildKit cache volume ensured (svsetup_buildkit_cache); DOCKER_BUILDKIT=1 set globally"
}

# update_self — git pull the toolkit itself from GitHub and re-exec.
update_self() {
  header "Updating svsetup from GitHub"
  if [ ! -d "${SVSETUP_DIR}/.git" ]; then
    warn "${SVSETUP_DIR} is not a git checkout — cannot self-update. Re-run the installer instead."
    return 1
  fi
  git -C "$SVSETUP_DIR" fetch --all -q || { warn "git fetch failed — check your network"; return 1; }
  local before after
  before="$(git -C "$SVSETUP_DIR" rev-parse --short HEAD)"
  git -C "$SVSETUP_DIR" reset --hard origin/main -q
  after="$(git -C "$SVSETUP_DIR" rev-parse --short HEAD)"
  chmod +x "${SVSETUP_DIR}/svsetup.sh" "${SVSETUP_DIR}"/modules/*.sh 2>/dev/null || true
  if [ "$before" = "$after" ]; then
    ok "Already up to date (${after})"
    return 0
  fi
  ok "Updated ${before} -> ${after}"
  info "Restarting svsetup with the new version..."
  exec "${SVSETUP_DIR}/svsetup.sh"
}
