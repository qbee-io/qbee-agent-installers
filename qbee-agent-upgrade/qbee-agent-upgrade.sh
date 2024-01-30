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

# This is a helper script to be able to upgrade qbee-agent <= 2023.46 to newer versions
# on debian and redhat compatible systems. Make sure to test this script on non-production 
# systems first.
#
# NB: This script does not support upgrades/downgrades to versions before 2023.XX
#

set -euo pipefail

if [[ ! -f "$1" ]]; then
  echo "ERROR: $1 does not exist, aborting..."
  exit 1
fi

check_package_name() {
  local pkg_name
  pkg_name="$1"

  if [[ "$pkg_name" != "qbee-agent" ]]; then
    echo "ERROR: package $pkg is not a qbee-agent package"
    exit 1
  fi
}

check_package_arch() {
  local system_arch
  local pkg_arch
  system_arch="$1"
  pkg_arch="$2"

  if [[ "$system_arch" != "$pkg_arch" ]]; then
    echo "ERROR: system arch $system_arch is not the same as package arch $pkg_arch"
    exit 1
  fi
}

check_package_version() {
  local existing_version
  local new_version
  existing_version="$1"
  new_version="$2"

  if [[ ! "$existing_version" =~ ^(2023\.[0-9]+|1\.2\.[0-9]+)$ ]]; then
    echo "ERROR: upgrade from version $existing_version is not supported with this script"
    exit 1
  fi

  if [[ "$new_version" =~ ^1\.[0-9]\.[0-9]+$ ]]; then
    echo "ERROR: downgrade to version $new_version is not supported with this script"
    exit 1
  fi

  if [[ "$existing_version" == "$new_version" ]]; then
    echo "ERROR: existing version $existing_version is the same as new version $new_version"
    exit 1
  fi
}

sanity_deb() {
  local pkg
  pkg="$1"

  pkg_name=$(dpkg -I "$pkg" | awk '/^[ ]*Package:/{print $NF}')

  check_package_name "$pkg_name"

  system_arch=$(dpkg --print-architecture)
  pkg_arch=$(dpkg -I "$pkg" | awk '/^[ ]*Architecture:/{print $NF}')

  check_package_arch "$system_arch" "$pkg_arch"

  existing_version=$(dpkg -s qbee-agent | awk '/^[ ]*Version:/{print $NF}')
  new_version=$(dpkg -I "$pkg" | awk '/^[ ]*Version:/{print $NF}')

  check_package_version "$existing_version" "$new_version"
}

sanity_rpm() {
  local pkg
  pkg="$1"

  pkg_name=$(rpm --queryformat='%{name}\n' "$pkg")

  check_package_name "$pkg_name"

  pkg_arch=$(rpm --queryformat='%{arch}\n' -qp "$pkg")
  system_arch=$(rpm --eval '%{_arch}')

  check_package_arch "$system_arch" "$pkg_arch"

  existing_version=$(rpm --queryformat='%{version}\n' -q qbee-agent)
  new_version=$(rpm --queryformat='%{version}\n' -qp "$pkg")

  check_package_version "$existing_version" "$new_version"
  
}

upgrade_rpm() {
  local pkg
  pkg="$1"

  # Upgrade rpm without running scripts
  rpm -Uvh --noscripts "$pkg"
}

upgrade_deb() {
  local pkg
  pkg="$1"

  # Fix issues with existing package
  rm -f /var/lib/dpkg/info/qbee-agent.prerm

  # Unpack the new qbee-agent
  dpkg --unpack "$pkg"

  # Fix any issues with new package
  rm -f /var/lib/dpkg/info/qbee-agent.postinst

  # Configure new package
  dpkg --configure qbee-agent
}

post_upgrade(){
  # Make sure that we have updated ca certs
  cp -a /opt/qbee/share/ssl/ca.cert /etc/qbee/ppkeys

  # Restart qbee-agent in non-blocking mode if running systemd
  if [[ -d /run/systemd/system ]]; then
    systemctl --no-block stop qbee-agent
    systemctl daemon-reload
    systemctl --no-block restart qbee-agent
  fi
  # Make sure that qbee-agent is enabled on boot
  systemctl enable qbee-agent
}

send_v1_logs() {
  # Attempt to get the logs from v1
  if [[ ! -d /var/lib/qbee/app_workdir/log ]]; then
	  return
  fi

  # Get contents of any v1 logs and remove if they exist
  num_logs=$(find /var/lib/qbee/app_workdir/log -type f | wc -l)	
  if [[ $num_logs -gt 0 ]]; then
	  cat /var/lib/qbee/app_workdir/log/policy_log-*.jsonl > /var/lib/qbee/app_workdir/reports.jsonl
	  rm -f /var/lib/qbee/app_workdir/log/policy_log-*.jsonl 
  fi
}

# resolve package manager
dpkg_path=$(command -v dpkg || true)
rpm_path=$(command -v rpm || true)

if [[ -n "${dpkg_path}" ]]; then
  sanity_deb "$1"
  upgrade_deb "$1"
elif [[ -n "${rpm_path}" ]]; then
  sanitiy_rpm "$1"
  upgrade_rpm "$1"
else
  echo "ERROR: package manager not supported"
  exit 1
fi

# Run post upgrade steps
post_upgrade

# Fetch logs from agent v1 if there are any
send_v1_logs
