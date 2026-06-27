#!/usr/bin/env bash
# 06-bots.sh — Telegram bots from Alirewa's GitHub: each ships its own
# production-ready install.sh (systemd service, isolated venv/Node deps,
# unique service/container names) — we just run the official installer.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

AUTOSENDER_URL="https://raw.githubusercontent.com/Alirewa/tg-bot-auto-sender/main/install.sh"
DRIVEBOT_URL="https://raw.githubusercontent.com/Alirewa/tg-bot-uploader-drive/main/install.sh"

module_bots() {
  header "Telegram Bots"
  echo "  1) tg-bot-auto-sender   — schedules/posts VPN configs to a Telegram channel"
  echo "  2) tg-bot-uploader-drive — uploads Telegram files to the user's Google Drive"
  echo "  3) Both"
  echo "  0) Back"
  local choice
  ask choice "Choose" "0"
  case "$choice" in
    1) install_autosender ;;
    2) install_drivebot ;;
    3) install_autosender; install_drivebot ;;
    *) return 0 ;;
  esac
  mark_done "bots"
}

install_autosender() {
  header "tg-bot-auto-sender"
  info "This bot needs no public port by default (it only talks outbound to Telegram)."
  ask_open_ports "tg-bot-auto-sender"
  info "Running the bot's own installer (Node.js runtime, systemd service, isolated dir /opt/tg-bot-auto-sender)..."
  run_remote_installer "$AUTOSENDER_URL"
  append_info_doc <<'EOF'

== [06] tg-bot-auto-sender ==
What it does: scrapes/validates V2Ray-style configs and auto-posts a working one to
your Telegram channel on a cron schedule; optionally tests configs with xray-core and
can auto-publish subscription files to a GitHub repo.
Service: systemctl status tg-bot-auto-sender   |   Panel: tgsender
Install dir: /opt/tg-bot-auto-sender   |   Config: /opt/tg-bot-auto-sender/.env
Runs natively via systemd (no Docker), isolated by its own service name — no overlap
with Coolify or x-ui.
EOF
  ok "tg-bot-auto-sender installed"
}

install_drivebot() {
  header "tg-bot-uploader-drive"
  info "By default this only needs port 8081 LOCALLY for its own Bot API container (not exposed publicly)."
  ask_open_ports "tg-bot-uploader-drive"
  info "Running the bot's own installer (Python 3.12 venv, isolated systemd service, dedicated Docker container for the local Bot API)..."
  run_remote_installer "$DRIVEBOT_URL"
  append_info_doc <<'EOF'

== [06] tg-bot-uploader-drive ==
What it does: lets your Telegram users authenticate their own Google Drive and upload
files/videos to it through the bot (per-user OAuth2, so it uses THEIR storage quota).
Service: systemctl status gdrive-uploader   |   CLI: tgdrive {logs|restart|stop|env|update}
Install dir: /opt/gdrive-uploader-bot (isolated Python venv at .venv)
Docker container: gdrive-bot-api on port 8081 — only used for the local Telegram Bot
API server; that port was intentionally NOT opened in UFW (default-deny), since it's
only needed locally by the bot itself, not by the public internet.
EOF
  ok "tg-bot-uploader-drive installed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  require_root; require_ubuntu
  module_bots
fi
