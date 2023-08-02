# qbee-agent-installers
This is the automated install and bootstrap scripts for qbee-agent.

# Usage

First, download the script:

```bash
$ wget -O /tmp/installer.sh -q https://raw.githubusercontent.com/qbee-io/qbee-agent-installers/main/installer.sh
```

Then, execute the installer:

```bash
$ sudo bash /tmp/installer.sh --bootstrap_key=<bootstrap_key>
``

Alternatively, you could run the installer as a oneliner:

```
$ wget -O - -q https://raw.githubusercontent.com/qbee-io/qbee-agent-installers/main/installer.sh | sudo bash -s -- --bootstrap_key=<bootstrap_key>
```
