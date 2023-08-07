# qbee-agent-installers
This is the automated install and bootstrap scripts for qbee-agent.

# Usage

First, download the script:

```bash
$ wget -O /tmp/qbee-agent-installer.sh -q https://raw.githubusercontent.com/qbee-io/qbee-agent-installers/main/qbee-agent-installer.sh
```

Then, execute the installer:

```bash
sudo bash /tmp/qbee-agent-installer.sh --bootstrap-key <bootstrap_key>
```

Alternatively, you could run the installer as a oneliner:

```bash
wget -O - -q https://raw.githubusercontent.com/qbee-io/qbee-agent-installers/main/qbee-agent-installer.sh | \
  sudo bash -s -- --bootstrap-key <bootstrap_key>
```

You can also run the docker-entrypoint.sh for testing qbee features with a docker container (NB: Software Management and Docker
Container management does not work in docker mode out of the box)

```bash
wget https://raw.githubusercontent.com/qbee-io/qbee-agent-installers/main/qbee-agent-entrypoint.sh
docker run -v $(pwd):/entrypoint:ro --cap-add NET_ADMIN --device /dev/net/tun -e QBEE_BOOTSTRAP_KEY=<bootstrap_key> debian:latest bash /entrypoint/qbee-agent-entrypoint.sh
```

NB! Some features are not available in the docker mode (like Docker Container Management and Software Management) as they require that
qbee-agent is run on a bare metal system.
