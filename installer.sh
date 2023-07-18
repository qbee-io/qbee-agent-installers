#!/usr/bin/env bash

## Some environment setup
set -e
export DEBIAN_FRONTEND=noninteractive

##
DEFAULT_QBEE_AGENT_VERSION="2023.26"

URL_BASE="https://cdn.qbee.io/software/qbee-agent"
# wget -O - -q https://raw.githubusercontent.com/qbee-io/qbee-agent-installers/main/installer.sh | bash -s -- --bootstrap_key=<bootstrap_key>

## Handle Arguments
usage() {
  printf "Installer version: $QBEE_AGENT_VERSION                     \\n"   
  printf "\\n"
  printf "Valid Arguments are:                                       \\n"
  printf " --qbee_agent_version=x.x.x                                \\n"
  printf " --bootstrap_key=<bootstrap_key>                           \\n"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --qbee_agent_version=*)
      QBEE_AGENT_VERSION="${1#*=}"
      ;;
    --bootstrap_key=*)
      BOOTSTRAP_KEY="${1#*=}"
      ;;
    *)
      exit 1
  esac
  shift
done

if [[ -z $QBEE_AGENT_VERSION ]]; then
  export QBEE_AGENT_VERSION="$DEFAULT_QBEE_AGENT_VERSION"
else
  export QBEE_AGENT_VERSION
fi

if [[ -z $BOOTSTRAP_KEY ]]; then
  echo "ERROR: No bootstrap key provided, exiting."
  usage
  exit 1
fi

## We only want to run as root
root_check() {
  if [[ $(whoami) != "root" ]]; then
    echo "This should only be run as root"
    exit 1
  fi
}

root_check
##

# determine the package manager
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

# determine the architecture
find_package_architecture() {
  if [[ $PACKAGE_MANAGER == "dpkg" ]]; then
    export PACKAGE_ARCHITECTURE=$(dpkg --print-architecture)
  elif [[ $PACKAGE_MANAGER == "rpm" ]]; then
    export PACKAGE_ARCHITECTURE=$(rpm --eval '%{_arch}')
  fi
}

# construct the agent url
get_qbee_agent_url() {
  # Check for which family of agent to install
  if [[ $QBEE_AGENT_VERSION =~ ^20.+$ ]]; then
    URL_BASE="${URL_BASE}/${QBEE_AGENT_VERSION}/packages"
  fi

  if [[ $PACKAGE_MANAGER == "dpkg" ]]; then
    export QBEE_AGENT_URL="${URL_BASE}/qbee-agent_${QBEE_AGENT_VERSION}_${PACKAGE_ARCHITECTURE}.deb"
  elif [[ $PACKAGE_MANAGER == "rpm" ]]; then
    export QBEE_AGENT_URL="${URL_BASE}/qbee-agent-${QBEE_AGENT_VERSION}-1.${PACKAGE_ARCHITECTURE}.rpm"
  fi
}

install_wget() {
  if [[ -z $(command -v wget) ]]; then
     if [[ $PACKAGE_MANAGER == "dpkg" ]]; then
        apt-get update
        apt-get install -y wget
      elif [[ $PACKAGE_MANAGER == "rpm" ]]; then
        yum install -y wget
      fi
  fi
}

# install the agent
install_qbee_agent() {
  if [[ $PACKAGE_MANAGER == "dpkg" ]]; then
    wget -O /tmp/qbee-agent.deb ${QBEE_AGENT_URL}
    dpkg -i /tmp/qbee-agent.deb
    rm -f /tmp/qbee-agent.deb
  elif [[ $PACKAGE_MANAGER == "rpm" ]]; then
    wget -O /tmp/qbee-agent.rpm ${QBEE_AGENT_URL}
    rpm -i /tmp/qbee-agent.rpm
    rm -f /tmp/qbee-agent.rpm
  fi
}

# bootstrap the agent
bootstrap_agent() {
  if [[ -f /etc/qbee/qbee-agent.json ]]; then
    echo "Agent already bootstrapped, skipping."
    return
  fi

  if [[ $QBEE_AGENT_VERSION =~ ^20.+$ ]]; then
    qbee-agent bootstrap -k ${BOOTSTRAP_KEY}
  else
    /opt/qbee/bin/qbee-bootstrap bootstrap -k ${BOOTSTRAP_KEY}
  fi
}

# restart the agent
start_qbee_agent() {
  if [ -f '/proc/1/comm' ]; then
    init_comm=$(cat /proc/1/comm)
    if [ "$init_comm" = "systemd" ]; then
      systemctl restart qbee-agent
    else
      echo "Not running systemd, please restart the agent manually."
      if [[ $QBEE_AGENT_VERSION =~ ^20.+$ ]]; then
        echo " $ qbee-agent start"
      else
        echo " $ /var/lib/qbee/bin/cf-execd -F"
      fi
    fi
  fi
}

detect_package_manager
find_package_architecture
get_qbee_agent_url
install_wget
install_qbee_agent
bootstrap_agent
start_qbee_agent

echo 'Installation complete.'
