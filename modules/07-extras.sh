#!/usr/bin/env bash
# 07-extras.sh — Optional, genuinely useful CLI tools for day-to-day server
# operation. Nothing here runs a network service or competes for a port.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

module_extras() {
  header "Extra Useful Packages"
  apt_update_once
  pkg_install htop glances ncdu tmux fzf bat tree jq net-tools dnsutils rsync zstd
  # Ubuntu ships bat's binary as `batcat`; add the conventional `bat` alias.
  if command -v batcat >/dev/null 2>&1 && ! command -v bat >/dev/null 2>&1; then
    ln -sf "$(command -v batcat)" /usr/local/bin/bat
  fi
  ok "Extra packages installed"

  append_info_doc <<'EOF'

== [07] Extra Packages ==
htop / glances  — interactive process & resource monitors (glances also shows
                  Docker container stats in one screen: top-level view of Coolify
                  vs x-ui resource usage).
ncdu            — interactive disk-usage explorer; run `ncdu /` to find what's
                  eating disk space (Docker images/volumes are the usual culprit).
tmux            — terminal multiplexer; keeps long-running commands alive after
                  you disconnect SSH.
fzf             — fuzzy finder; pipe any list into it or press Ctrl-R for fuzzy
                  shell-history search.
bat             — `cat` with syntax highlighting and line numbers (aliased from
                  `batcat`, Ubuntu's package name for it).
tree            — visualize a directory structure at a glance.
jq              — parse/query JSON from the CLI (handy for Coolify/x-ui API output).
net-tools/dnsutils — netstat, ifconfig, dig, nslookup — classic network diagnostics.
rsync           — fast incremental file sync/backups.
zstd            — very fast compression; useful for quick backups of /opt/* volumes.

Deliberately NOT installed: a second web server (nginx/apache/caddy). Coolify already
runs Traefik on ports 80/443 — adding another proxy would only create port conflicts
or add latency, not improve performance.
EOF

  mark_done "extras"
  ok "Step 5/5 complete: extra packages installed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  require_root; require_ubuntu
  module_extras
fi
