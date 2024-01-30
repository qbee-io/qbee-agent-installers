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

set -e
export DEBIAN_FRONTEND=noninteractive

cleanup() {
    echo "Caught signal, exiting qbee demo docker container..."
    exit
}

progress() {
  local pid=$1
  while kill -0 "$pid" 2>/dev/null; do
    printf "."
    sleep .5
  done
  wait "$pid" # capture exit code
  printf "\n"
  return $?
}

exec_command() {
  ("$@" > /dev/null 2>&1) &
  progress $!
}

trap cleanup INT TERM

if [[ -z $QBEE_BOOTSTRAP_KEY ]]; then
  echo "ERROR: No bootstrap key has been provided"
fi

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

install_utils() {
  if [[ $PACKAGE_MANAGER == "dpkg" ]]; then
    echo "Updating package cache"
    exec_command apt-get update
    echo "Installing utilities"
    exec_command apt-get install -y wget openssh-server iproute2 sudo
  elif [[ $PACKAGE_MANAGER == "rpm" ]]; then
    echo "Installing utilities"
    exec_command yum install -y wget openssh-server iproute sudo
  fi
}

generate_user_password() {
  < /dev/urandom tr -dc A-Z-a-z-0-9 | head -c 8
  echo
}

configure_user_access() {
  # add user and password
  useradd -c "$DEMO_USER,,,,qbee demo user" -m -s /bin/bash $DEMO_USER
  echo "$DEMO_USER:$DEMO_PASSWORD" | chpasswd 

  # enable passwordless sudo
  echo "$DEMO_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/qbee
  chmod 600 /etc/sudoers.d/qbee

  # start sshd
  mkdir -p /run/sshd
  /usr/sbin/sshd 
}

install_qbee() {
  local basedir
  basedir=$(cd "$(dirname ${0})" && pwd)

  install_script=$(mktemp /tmp/qbee-agent-installer.sh.XXXXXXXX)
  echo "Downloading install script"
  exec_command wget -O "$install_script" -q https://raw.githubusercontent.com/qbee-io/qbee-agent-installers/main/qbee-agent-installer.sh

  # Utilities are already installed
  export QBEE_SKIP_UTILITIES_INSTALL=1
  echo "Installing and bootstrapping qbee-agent"
  exec_command bash "$install_script" --bootstrap-key "$QBEE_BOOTSTRAP_KEY"
  rm "$install_script" -f
}

DEMO_USER="qbee"
DEMO_PASSWORD=$(generate_user_password)

detect_package_manager
install_utils
configure_user_access
install_qbee

echo "****************************************************"
echo "* Starting qbee-agent in docker for demo purposes   "
echo "*                                                   "
echo "* Remote console login is for this container is:    "
echo "*   username: $DEMO_USER                            "
echo "*   password: $DEMO_PASSWORD                        "
echo "****************************************************"

# start qbee agent scheduler
qbee-agent start &
wait $!
