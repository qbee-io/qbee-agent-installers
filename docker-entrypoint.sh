#!/usr/bin/env bash

cleanup() {
    echo "Caught signal, exiting qbee demo docker container..."
    exit
}

trap cleanup INT TERM

while [[ $# -gt 0 ]]; do
  case "$1" in
    --qbee-agent-version)
      shift
      QBEE_AGENT_VERSION=$1
      ;;
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
    export PACKAGE_MANAGER="dpkg"
  elif [[ -n $(command -v rpm) ]]; then
    export PACKAGE_MANAGER="rpm"
  else
    echo "No supported package manager found, exiting."
    exit 1
  fi   
}

install_utils() {
 if [[ $PACKAGE_MANAGER == "dpkg" ]]; then
    apt-get update
    apt-get install -y wget openssh-server iproute2
 elif [[ $PACKAGE_MANAGER == "rpm" ]]; then
    yum install -y wget openssh-server iproute
 fi
}

generate_user_password() {
  < /dev/urandom tr -dc A-Z-a-z-0-9 | head -c${1:-16}
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
  wget -O - -q https://raw.githubusercontent.com/qbee-io/qbee-agent-installers/main/installer.sh | \
    bash -s -- --bootstrap-key $BOOTSTRAP_KEY
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
