#!/usr/bin/env bash

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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bootstrap-key)
      shift
      BOOTSTRAP_KEY=$1
      ;;
    *)
      exit 1
  esac
  shift
done

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
    echo "Installing dependencies"
    exec_command apt-get install -y wget openssh-server iproute2
  elif [[ $PACKAGE_MANAGER == "rpm" ]]; then
    echo "Installing dependencies"
    exec_command yum install -y wget openssh-server iproute
  fi
}

generate_user_password() {
  < /dev/urandom tr -dc A-Z-a-z-0-9 | head -c 8
  echo
}

start_openssh() {
  useradd -c "qbeedemo,,,,qbee demo user" -m -s /bin/bash qbeedemo
  echo "$DEMO_USER:$DEMO_PASSWORD" | chpasswd 
  # start sshd
  mkdir -p /run/sshd
  /usr/sbin/sshd 
}

install_qbee() {
  local basedir
  basedir=$(cd "$(dirname ${0})" && pwd)

  if [[ -f "$basedir/installer.sh" ]]; then
    echo "Installing qbee-agent"
    exec_command bash "$basedir/installer.sh" --bootstrap-key "$BOOTSTRAP_KEY"
  else
    install_script=$(mktemp /tmp/installer.sh.XXXXXXXX)
    echo "Downloading install script"
    exec_command wget -O "$install_script" -q https://raw.githubusercontent.com/qbee-io/qbee-agent-installers/main/installer.sh
    echo "Installing qbee-agent" 
    exec_command bash "$install_script" --bootstrap-key "$BOOTSTRAP_KEY"
    rm "$install_script" -f
  fi
}

DEMO_USER="qbeedemo"
DEMO_PASSWORD=$(generate_user_password)

detect_package_manager
install_utils
start_openssh
install_qbee

echo "****************************************************"
echo "* Starting qbee-agent in docker for demo purposes   "
echo "*                                                   "
echo "* Remote console login is for this container is:    "
echo "*   username: $DEMO_USER                            "
echo "*   password: $DEMO_PASSWORD                        "
echo "****************************************************"

# start qbee agent scheduler
qbee-agent start
