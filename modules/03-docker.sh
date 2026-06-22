#!/usr/bin/env bash
# 03-docker.sh — Docker Engine + Compose plugin, installed early so every panel
# below (Coolify, bot containers) runs isolated. Log rotation + BuildKit enabled.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

module_docker() {
  header "Docker Engine"
  if command -v docker >/dev/null 2>&1; then
    ok "Docker already installed ($(docker --version))"
  else
    install_docker
  fi

  configure_daemon
  systemctl enable --now docker >/dev/null 2>&1
  ok "Docker service enabled and running"

  append_info_doc <<'EOF'

== [03] Docker ==
- Docker Engine + the `docker compose` plugin, installed from Docker's official apt repo.
- Every panel below (Coolify, 3x-ui's nothing, the Telegram bots) runs in its own
  container/isolated process — nothing shares a runtime or a Python/Node environment.
- Container log rotation capped at 10MB x 3 files per container so logs cannot fill disk.
- BuildKit enabled by default for faster, cached image builds (faster Coolify deploys).
EOF

  mark_done "docker"
  ok "Step 3/5 complete: Docker ready"
}

install_docker() {
  info "Installing Docker Engine from the official Docker apt repository..."
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  . /etc/os-release
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME:-$VERSION_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  pkg_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  ok "Docker Engine installed ($(docker --version))"
}

configure_daemon() {
  mkdir -p /etc/docker
  cat > /etc/docker/daemon.json <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "features": { "buildkit": true }
}
EOF
  ok "Docker daemon configured: log rotation + BuildKit"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  require_root; require_ubuntu
  module_docker
fi
