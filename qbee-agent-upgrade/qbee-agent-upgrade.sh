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
# NB: This script does not support downgrades
#

set -euo pipefail

if [[ ! -f "$1" ]]; then
  echo "ERROR: $1 does not exist, aborting..."
  exit 1
fi

check_system_utilities() {
  if [[ ! -x "$(command -v mktemp)" ]]; then
    echo "ERROR: mktemp is required to run this script"
    exit 1
  fi
}

check_agent_sanity() {
  if [[ ! -f /etc/qbee/qbee-agent.json ]]; then
    echo "ERROR: qbee-agent configuration file not found"
    exit 1
  fi

  if [[ ! -f /etc/qbee/ppkeys/qbee.cert ]]; then
    echo "ERROR: qbee-agent certificate not found"
    exit 1
  fi

  if [[ ! -f /etc/qbee/ppkeys/qbee.key ]]; then
    echo "ERROR: qbee-agent key not found"
    exit 1
  fi
}

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

check_dpkg_lock() {
  if ls -lt /proc/[0-9]*/fd 2> /dev/null | grep -q /var/lib/dpkg/lock; then
    echo "ERROR: Package manager is already running, unable to upgrade" 
    exit 1
  fi
}

sanity_deb() {
  local pkg
  pkg="$1"

  check_dpkg_lock

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

# resolve package manager
dpkg_path=$(command -v dpkg || true)
rpm_path=$(command -v rpm || true)

check_system_utilities

if [[ -n "${dpkg_path}" ]]; then
  sanity_deb "$1"
elif [[ -n "${rpm_path}" ]]; then
  sanitiy_rpm "$1"
else
  echo "ERROR: package manager not supported"
  exit 1
fi

# Passed the sanity checking, we can now upgrade the package
UPGRADE_SCRIPT=$(mktemp /tmp/qbee-agent-do-upgrade.XXXXXXXXX.sh)
cat <<EOF > "${UPGRADE_SCRIPT}"
#!/usr/bin/env bash
set -ue
EOF

if [[ -n "${dpkg_path}" ]]; then

  cat <<'EOF' >> "${UPGRADE_SCRIPT}"
# Wait for dpkg lock to be released, there could be apt/dpkg processes running
while ls -lt /proc/[0-9]*/fd 2> /dev/null | grep -q /var/lib/dpkg/lock; do
  sleep 1
done

dpkg -i "$1"
EOF

elif [[ -n "${rpm_path}" ]]; then
  cat <<'EOF' >> "${UPGRADE_SCRIPT}"
rpm -Uvh "$1"
EOF

fi

cat <<'EOF' >> "${UPGRADE_SCRIPT}"
# Attempt to get the logs from v1
if [[ -d /var/lib/qbee/app_workdir/log ]]; then
  # Get contents of any v1 logs and remove if they exist
  num_logs=$(find /var/lib/qbee/app_workdir/log -type f | wc -l)	
  if [[ $num_logs -gt 0 ]]; then
	  cat /var/lib/qbee/app_workdir/log/policy_log-*.jsonl > /var/lib/qbee/app_workdir/reports.jsonl
	  rm -f /var/lib/qbee/app_workdir/log/policy_log-*.jsonl 
  fi
fi

# Make sure we reload the systemd daemon
systemctl daemon-reload

# Make sure that qbee-agent is enabled on boot
systemctl enable qbee-agent

while ! systemctl -q is-active qbee-agent; do
  systemctl restart qbee-agent
  sleep 10
done

# remove the upgrade script
rm "$0" -f

# End of upgrade script
EOF

echo "Sanity check completed, starting upgrade procedure as background task"

chmod +x "${UPGRADE_SCRIPT}"
# Start the upgrade procedure itself in the background
$UPGRADE_SCRIPT "$1" < /dev/null > /dev/null 2>&1 &

exit 0