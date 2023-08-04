# qbee-agent-installers
This is the automated install and bootstrap scripts for qbee-agent.

# Usage

First, download the script:

```bash
$ wget -O /tmp/installer.sh -q https://raw.githubusercontent.com/qbee-io/qbee-agent-installers/main/installer.sh
```

Then, execute the installer:

```bash
$ sudo bash /tmp/installer.sh --bootstrap-key <bootstrap_key>
```

Alternatively, you could run the installer as a oneliner:

```bash
$ wget -O - -q https://raw.githubusercontent.com/qbee-io/qbee-agent-installers/main/installer.sh | \
  sudo bash -s -- --bootstrap-key <bootstrap_key>
```

You can also run the docker-entrypoint.sh for testing qbee features with a docker container (NB: Software Management and Docker
Container management does not work in docker mode out of the box)

```bash
$ wget https://raw.githubusercontent.com/qbee-io/qbee-agent-installers/main/installer.sh
$ docker run -it -v $(pwd):/installer:ro --cap-add NET_ADMIN --device /dev/net/tun debian:latest bash /installer/docker-entrypoint.sh --bootstrap-key <bootstrap_key>
```
