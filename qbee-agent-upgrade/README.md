## qbee-agent-upgrade.sh

qbee-agent-upgrade.sh is a helper script to be able to upgrade qbee-agent versions <= 2023.XX through the qbee file distribution mechanism.

## How to use

1. Get the qbee-agent-upgrade.sh script and upload it to the file manager
2. Get the latest package corresponding from https://www.app.qbee.io/#/qbee-packages and upload it do the qbee-file-manager
3. Create a file distribution to distribute both the script and the package file and run the script pointing to the package in post command:
Eg.
```
bash /path/to/qbee-agent-upgrade.sh /path/to/qbee-agent_2024.09_amd64.deb
```

## Example file distribution payload

