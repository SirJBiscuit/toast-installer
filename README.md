# Toast Node Installer

An interactive Bash script for setting up and hardening new Pterodactyl Panel nodes on Debian-based systems (Debian 11/12, Ubuntu 20.04/22.04).

This script automates the installation of all necessary components for a Pterodactyl node and includes optional security and performance enhancements.

## Installation

Run the following command as root on your new server to download and install the script:

```bash
sudo curl -sSL [https://raw.githubusercontent.com/SirJBiscuit/toast-installer/main/nodeinstaller.sh](https://raw.githubusercontent.com/SirJBiscuit/toast-installer/main/nodeinstaller.sh) | sed 's/\r$//' | sudo tee /usr/local/bin/toastinstall > /dev/null
