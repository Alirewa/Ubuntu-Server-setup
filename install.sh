#!/usr/bin/env bash
# install.sh — bootstrap for Ubuntu-Server-setup.
#
#   curl -fsSL https://raw.githubusercontent.com/Alirewa/Ubuntu-Server-setup/main/install.sh -o svsetup-install.sh
#   sudo bash svsetup-install.sh
#
# Clones/updates the toolkit to /opt/svsetup, installs the `svsetup` command,
# then launches the interactive control panel.
set -euo pipefail

REPO_URL="${SVSETUP_REPO_URL:-https://github.com/Alirewa/Ubuntu-Server-setup.git}"
INSTALL_DIR="${SVSETUP_DIR:-/opt/svsetup}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root: sudo bash $0" >&2
  exit 1
fi

if [ ! -f /etc/os-release ] || ! grep -qi ubuntu /etc/os-release; then
  echo "This toolkit only supports Ubuntu (22.04/24.04)." >&2
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git ca-certificates
fi

if [ -d "${INSTALL_DIR}/.git" ]; then
  echo "[INFO] Updating existing svsetup install at ${INSTALL_DIR}..."
  git -C "$INSTALL_DIR" fetch --all -q
  git -C "$INSTALL_DIR" reset --hard origin/main -q
else
  echo "[INFO] Cloning Ubuntu-Server-setup to ${INSTALL_DIR}..."
  git clone -q "$REPO_URL" "$INSTALL_DIR"
fi

chmod +x "${INSTALL_DIR}/svsetup.sh" "${INSTALL_DIR}"/modules/*.sh
ln -sf "${INSTALL_DIR}/svsetup.sh" /usr/local/bin/svsetup

echo "[OK] svsetup installed. Launching the control panel..."
echo "[OK] You can re-open it any time with: sudo svsetup"
echo
exec "${INSTALL_DIR}/svsetup.sh"
