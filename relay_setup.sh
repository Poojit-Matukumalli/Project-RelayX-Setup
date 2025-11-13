#!/usr/bin/env bash
# Project RelayX bash file for setup 

set -euo pipefail

# Configuring directories
RELAY_SCRIPT=Server_RelayX.py
SERVICE_NAME=RelayX
WORKDIR=$HOME
TORRC_PATH=/etc/tor/torrc

echo "                                                 Welcome to RelayX Setup" && echo
echo "This script is for Auto installation"
echo " For manual installation, terminate this script and do it manually. Instructions are in GitHub RELAYSETUP.md" && echo && echo
echo "For security, we recommend running in a non sudo profile (no root access)"
echo && echo "               Non sudo profile setup"
read -p "Hostname for the non sudo profile (remember this): " profile_hostname
read -s -p "Password for $profile_hostname: " profile_password
echo 
profile_hostname=$(echo $profile_hostname | tr -cd '[:alnum:]_-')
sudo adduser --gecos "" --disabled-password $profile_hostname
echo "$profile_hostname:$profile_password" | sudo chpasswd
echo "Non Sudo profile with name $profile_hostname has been created" && echo

echo "Updating system and installing dependencies..."
sudo apt-get update
sudo apt install -y software-properties-common
clear && sudo add-apt-repository -y ppa:deadsnakes/ppa
clear && sudo apt -y upgrade
clear && sudo apt-get install -y tor python3.13 python3-pip ufw nano 

echo "Installing Python packages..."
pip3 install --upgrade pip
sudo apt install python3-aiohttp-socks
sudo apt install python3-aiofiles

# Python RelayX daemon
TargetDir=/home/$profile_hostname
sudo mv /home/Project-RelayX-Setup "$TargetDir"
SERVICE_PATH=/etc/systemd/system/$SERVICE_NAME.service
echo "Creating systemd service for relay..."
sudo tee "$SERVICE_PATH" > /dev/null <<EOF
[Unit]
Description=RelayX Daemon Service
After=network.target

[Service]
Type=simple
User=$profile_hostname
WorkingDirectory=/home/$profile_hostname
ExecStart=/usr/bin/python3.13 /home/Project-RelayX-Setup/$RELAY_SCRIPT
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"
sudo systemctl start "$SERVICE_NAME"
sudo systemctl status "$SERVICE_NAME" --no-pager

# Tor setup
echo "Configuring Tor..."
# tor check
sudo systemctl enable tor
sudo systemctl start tor
sudo systemctl status tor --no-pager

# firewall setup
if command -v ufw >/dev/null 2>&1; then
    echo "Allowing Tor ports through ufw..."
    sudo ufw allow 9050/tcp
    sudo ufw reload || true
fi

# fetch hostname
HOSTNAME_FILE="$HOME/.tor/hostname"
if [[ ! -f "$HOSTNAME_FILE" ]]; then
    # Default Tor hostname location
    HOSTNAME_FILE="/var/lib/tor/hostname"
fi

echo "Fetching relay hostname..."
if [[ -f "$HOSTNAME_FILE" ]]; then
    echo "Your relay hostname is:"
    sudo cat "$HOSTNAME_FILE"
else
    echo "Could not find Tor hostname file. Ensure Tor is running."
fi

echo "Project RelayX setup complete."
echo "Add the above hostname via a PR to the relay_list in the main repo"
