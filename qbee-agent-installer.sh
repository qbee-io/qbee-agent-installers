#!/usr/bin/env bash

# Copyright 2025 qbee.io
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# SPDX-License-Identifier: Apache-2.0

# --- Setup environment ---
set -euo pipefail

REPO="qbee-io/qbee-agent"
API="https://api.github.com/repos/$REPO/releases/latest"
WORKDIR="${TMPDIR:-/tmp}/qbee-agent-install.$$"

die() { echo "Error: $*" >&2; exit 1; }
info(){ echo "==> $*"; }
cleanup(){ [ -d "$WORKDIR" ] && rm -rf "$WORKDIR"; }
trap cleanup EXIT INT TERM

# --- Check whether we have wget or curl ---
if [[ -n $(command -v wget) ]]; then
  GET="wget -qO-"
elif [[ -n $(command -v curl) ]]; then
  GET="curl -sSL"
else
  die "No suitable download tool found. Please install curl or wget and try again."
fi

# --- Check whether we are running as root ---
if [[ $(whoami) != "root" ]]; then
    die "This should only be run as root"
fi

# --- Switch to workdir ---
mkdir -p "$WORKDIR" || die "Cannot create temp dir"
info "Switching to workdir: $WORKDIR"
cd $WORKDIR

# --- Detect command line options ----
usage() {
  echo "Installer for the latest qbee-agent package"
  echo "Usage: qbee-agent-installer.sh [OPTIONS]"
  echo ""
  echo "Valid OPTIONS are:"
  echo " --bootstrap-key <bootstrap_key>"
}

QBEE_BOOTSTRAP_KEY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bootstrap-key)
      shift
      QBEE_BOOTSTRAP_KEY=$1
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Invalid option $1"
      usage
      exit 1
  esac
  shift
done

# --- Resolve qbee agent version ---
JSON="$($GET "$API")" || die "Failed to query latest release"
TAG="$(printf '%s\n' "$JSON" | awk -F'"' '/"tag_name"[[:space:]]*:/ {print $4; exit}')"

case $TAG in
  *.*.*) PKG_VERSION="$TAG" ;;
  *.*)   PKG_VERSION="${TAG}.0" ;;
  *)     die "Unexpected tag format: $TAG" ;;
esac

info "Detected release: $TAG"

# --- Detect package manager and architecture ---
if [[ -n $(command -v dpkg) ]]; then
  PACKAGE_MANAGER="dpkg"

  PACKAGE_ARCHITECTURE=$(dpkg --print-architecture)
  case $PACKAGE_ARCHITECTURE in
    amd64|arm64|armhf|mips64el|riscv64) info "Detected architecture: $PACKAGE_ARCHITECTURE" ;;
    *) die "Unsupported architecture: $PACKAGE_ARCHITECTURE" ;;
  esac

  export DEBIAN_FRONTEND=noninteractive

  PACKAGE_FILE="qbee-agent_${PKG_VERSION}_${PACKAGE_ARCHITECTURE}.deb"

  INSTALL_CMD="dpkg -i"

elif [[ -n $(command -v rpm) ]]; then
  PACKAGE_MANAGER="rpm"

  PACKAGE_ARCHITECTURE=$(rpm --eval '%{_arch}')
  case $PACKAGE_ARCHITECTURE in
    x86_64|aarch64|armv7hl|mips64el|riscv64|riscv64) info "Detected architecture: $PACKAGE_ARCHITECTURE" ;;
    *) die "Unsupported architecture: $PACKAGE_ARCHITECTURE" ;;
  esac

  PACKAGE_FILE="qbee-agent-${PKG_VERSION}-1.${PACKAGE_ARCHITECTURE}.rpm"

  INSTALL_CMD="rpm -iU"

else
  die "No supported package manager found, exiting."
fi   

info "Detected package manager: $PACKAGE_MANAGER"

# --- Download package ---
DOWNLOAD_BASE_URL="https://github.com/$REPO/releases/download/$TAG"
CHECKSUM_URL="$DOWNLOAD_BASE_URL/checksums.txt"
PACKAGE_URL="$DOWNLOAD_BASE_URL/${PACKAGE_FILE}"

info "Downloading checksums: $CHECKSUM_URL"
$GET $CHECKSUM_URL > checksums.txt || die "Failed to download checksums"

info "Downloading package: $PACKAGE_URL"
$GET $PACKAGE_URL > $PACKAGE_FILE || die "Failed to download package $PACKAGE_FILE"

# --- Verify checksum ---
PKG_CHECKSUM=$(grep "$PACKAGE_FILE" checksums.txt)

info "Verifying checksum $PKG_CHECKSUM"
echo "$PKG_CHECKSUM" | sha256sum -c - || die "Checksum verification failed"

# --- Install package ---

info "Installing $PACKAGE_FILE"

$INSTALL_CMD $PACKAGE_FILE

# --- Bootstrap device ---
if [[ -z $QBEE_BOOTSTRAP_KEY ]]; then
  info "No bootstrap key provided."
  info "Use 'qbee-agent bootstrap -k <bootstrap-key>' command to bootstrap."
  exit 0
fi

if [[ -f /etc/qbee/qbee-agent.json ]]; then
  info "Agent already bootstrapped, skipping."
else
  info "Bootstrapping agent with key: $QBEE_BOOTSTRAP_KEY"
  qbee-agent bootstrap -k "$QBEE_BOOTSTRAP_KEY" || die "Failed to bootstrap agent"
fi

# --- Restart systemd service ---
if [ -f '/proc/1/comm' ]; then
  init_comm=$(cat /proc/1/comm)
  if [ "$init_comm" = "systemd" ]; then
    info "Restarting qbee-agent service"
    systemctl --no-block restart qbee-agent
  else
    info "Not running systemd, please start the agent manually."
    info "qbee-agent start"
  fi
fi
