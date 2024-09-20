#!/usr/bin/env bash

# Copyright 2024 qbee.io
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

## Some environment setup
set -e
export DEBIAN_FRONTEND=noninteractive

QBEE_DEVICE_HUB_HOST=${QBEE_DEVICE_HUB_HOST:-device.app.qbee.io}
QBEE_DEVICE_HUB_PORT=${QBEE_DEVICE_HUB_PORT:-}
QBEE_DEVICE_VPN_SERVER=${QBEE_DEVICE_VPN_SERVER:-vpn.app.qbee.io}
QBEE_DEVICE_CA_CERT=${QBEE_DEVICE_CA_CERT:-}

URL_BASE="https://cdn.qbee.io/software/qbee-agent"
REMOTE_ACCESS_VERSION="1"

usage() {
  echo "Installer for qbee-agent packages (versions 2023.XX and later)"
  echo "Usage: qbee-agent-installer.sh [OPTIONS]                      "
  echo "                                                              "
  echo "Valid OPTIONS are:                                            "
  echo " --bootstrap-key <bootstrap_key>                              "
  echo " --qbee-agent-version <qbee_agent_version> (default: latest)  "
  echo " --ca-cert <path_to_ca_cert> (optional)                            "
  echo " --device-hub-host <device_hub_host> (optional)               "
  echo " --device-hub-port <device_hub_port> (optional)               "
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --qbee-agent-version)
      shift
      QBEE_AGENT_VERSION=$1
      ;;
    --bootstrap-key)
      shift
      QBEE_BOOTSTRAP_KEY=$1
      ;;
    --ca-cert)
      shift
      QBEE_DEVICE_CA_CERT=$1
      ;;
    --device-hub-host)
      shift
      QBEE_DEVICE_HUB_HOST=$1
      ;;
    --device-hub-port)
      shift
      QBEE_DEVICE_HUB_PORT=$1
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

if [[ -z $QBEE_BOOTSTRAP_KEY ]]; then
  echo "WARNING: No bootstrap key provided, will only install"
fi

## We only want to run as root
root_check() {
  if [[ $(whoami) != "root" ]]; then
    echo "This should only be run as root"
    exit 1
  fi
}

root_check

# determine the package manager
detect_package_manager() {
  if [[ -n $(command -v dpkg) ]]; then
    PACKAGE_MANAGER="dpkg"
  elif [[ -n $(command -v rpm) ]]; then
    PACKAGE_MANAGER="rpm"
  else
    echo "No supported package manager found, exiting."
    exit 1
  fi   
}

# determine the architecture
find_package_architecture() {
  if [[ $PACKAGE_MANAGER == "dpkg" ]]; then
    PACKAGE_ARCHITECTURE=$(dpkg --print-architecture)
  elif [[ $PACKAGE_MANAGER == "rpm" ]]; then
    PACKAGE_ARCHITECTURE=$(rpm --eval '%{_arch}')
  fi
}

# resolve qbee agent version
resolve_qbee_agent_version() {
  if [[ -z $QBEE_AGENT_VERSION ]]; then
    QBEE_AGENT_VERSION=$(wget -O - -q https://cdn.qbee.io/software/qbee-agent/latest.txt)
    echo "Latest agent version is $QBEE_AGENT_VERSION"
  fi

  MAJOR_VERSION=$(echo "$QBEE_AGENT_VERSION" | cut -d. -f1)
  MINOR_VERSION=$(echo "$QBEE_AGENT_VERSION" | cut -d. -f2 | sed 's/^0*//')

  if [[ "$MAJOR_VERSION" -le 1 ]]; then
    echo "Agent version $QBEE_AGENT_VERSION is not supported, exiting."
    exit 1
  fi

  # Versions from 2024.09 and upwards have new remote access
  if [[ "$MAJOR_VERSION" -ge 2024 && "$MINOR_VERSION" -ge 9 ]]; then
    REMOTE_ACCESS_VERSION="2"
  fi
}

# construct the agent url
get_qbee_agent_url() {

  URL_BASE="${URL_BASE}/${QBEE_AGENT_VERSION}/packages"

  if [[ $PACKAGE_MANAGER == "dpkg" ]]; then
    QBEE_AGENT_PKG="qbee-agent_${QBEE_AGENT_VERSION}_${PACKAGE_ARCHITECTURE}.deb"
  elif [[ $PACKAGE_MANAGER == "rpm" ]]; then
    QBEE_AGENT_PKG="qbee-agent-${QBEE_AGENT_VERSION}-1.${PACKAGE_ARCHITECTURE}.rpm"
  fi
}

# make sure we have wget so that we can download the agent
install_wget () {
  local wget_cmd
  wget_cmd=$(command -v wget || true)
  if [[ -n $wget_cmd ]]; then
    return
  fi

  if [[ $PACKAGE_MANAGER == "dpkg" ]]; then
    apt-get update
    apt-get install -y wget
  elif [[ $PACKAGE_MANAGER == "rpm" ]]; then
    yum install -y wget
  fi
}

# install the utilities for remote access v1
install_utils_remote_access_v1_utils() {
  if [[ $PACKAGE_MANAGER == "dpkg" ]]; then
    apt-get install -y iproute2 openssh-server
  elif [[ $PACKAGE_MANAGER == "rpm" ]]; then
    yum install -y iproute openssh-server
  fi
}

# install the agent
install_qbee_agent() {
  local old_wd
  old_wd=$(pwd)

  DOWNLOAD_DIR=$(mktemp -d /tmp/qbee-agent-download.XXXXXXXX)
  wget -P "$DOWNLOAD_DIR" "${URL_BASE}/${QBEE_AGENT_PKG}"
  wget -P "$DOWNLOAD_DIR" "${URL_BASE}/SHA512SUMS"

  cd "$DOWNLOAD_DIR"
  PACKAGE_SHA512SUM=$(grep "${QBEE_AGENT_PKG}$" SHA512SUMS)
  echo "$PACKAGE_SHA512SUM" | sha512sum -c || exit 1

  if [[ $PACKAGE_MANAGER == "dpkg" ]]; then
    dpkg -i "${DOWNLOAD_DIR}/${QBEE_AGENT_PKG}"
  elif [[ $PACKAGE_MANAGER == "rpm" ]]; then
    rpm -iU "${DOWNLOAD_DIR}/${QBEE_AGENT_PKG}"
  fi
  rm "${DOWNLOAD_DIR}" -rf
  cd "$old_wd"
}

# bootstrap the agent
bootstrap_agent() {
  if [[ -f /etc/qbee/qbee-agent.json ]]; then
    echo "Agent already bootstrapped, skipping."
    return
  fi

  EXTRA_OPTIONS=""

  if [[ $REMOTE_ACCESS_VERSION -eq 1 ]]; then
    EXTRA_OPTIONS="--vpn-server $QBEE_DEVICE_VPN_SERVER"
  fi

  if [[ -n $QBEE_DEVICE_CA_CERT ]]; then
    EXTRA_OPTIONS="$EXTRA_OPTIONS --ca-cert $QBEE_DEVICE_CA_CERT"
  fi

  if [[ -n $QBEE_DEVICE_HUB_PORT ]]; then
    EXTRA_OPTIONS="$EXTRA_OPTIONS --device-hub-port $QBEE_DEVICE_HUB_PORT"
  fi

  # We allow word splitting here as theese are command line arguments
  # shellcheck disable=SC2086
  qbee-agent bootstrap -k "${QBEE_BOOTSTRAP_KEY}" --device-hub-host "$QBEE_DEVICE_HUB_HOST" $EXTRA_OPTIONS
}

# restart the agent
start_qbee_agent() {
  if [ -f '/proc/1/comm' ]; then
    init_comm=$(cat /proc/1/comm)
    if [ "$init_comm" = "systemd" ]; then
      systemctl --no-block restart qbee-agent
    else
      echo "Not running systemd, please start the agent manually."
      echo " $ qbee-agent start"
    fi
  fi
}

detect_package_manager
find_package_architecture
install_wget
resolve_qbee_agent_version

if [[ $REMOTE_ACCESS_VERSION -eq 1 ]]; then
  install_utils_remote_access_v1_utils
fi

get_qbee_agent_url
install_qbee_agent

# skip bootstrap if env variable set
[[ -z $QBEE_BOOTSTRAP_KEY ]] && exit 0

bootstrap_agent
start_qbee_agent
