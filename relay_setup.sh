#!/usr/bin/env bash
# Project RelayX bash file for setup 

set -euo pipefail

# Configuring directories
RELAY_SCRIPT="Server_RelayX"
SERVICE_NAME="RelayX"
WORKDIR="$HOME"
TORRC_PATH="/etc/tor/torrc"

echo "Welcome to Project RelayX Setup"
echo "Choose installation mode:"
echo "1) Auto install (recommended for non-technical users)"
echo "2) Manual install (sysadmins, advanced users)"
read -rp "Enter 1 or 2: " MODE

if [[ "$MODE" == "1" ]]; then
    echo "Auto mode selected"

    echo "Updating system and installing dependencies..."
    sudo apt-get update
    sudo apt install -y software-properties-common
    clear && sudo add-apt-repository -y ppa:deadsnakes/ppa
    clear && sudo apt -y upgrade
    clear && sudo apt-get install -y tor python3 python3-pip ufw nano 

    echo "Installing Python packages..."
    pip3 install --upgrade pip
    sudo apt install python3-aiohttp-socks

elif [[ "$MODE" == "2" ]]; then
    echo "--- Manual mode selected ---"
    echo "Please ensure the following are installed manually:"
    echo "1) Tor"
    echo "3) Python3 + pip3"
    echo "4) aiohttp-socks (pip3 install aiohttp-socks)"
    read -rp "Press Enter when ready..."
else
    echo "Invalid selection. Exiting."
    exit 1
fi

# Python RelayX daemon

SERVICE_PATH="/etc/systemd/system/$SERVICE_NAME.service"
echo "Creating systemd service for relay..."
sudo tee "$SERVICE_PATH" > /dev/null <<EOF
[Unit]
Description=RelayX Daemon Service
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$WORKDIR
ExecStart=/usr/bin/python3 $WORKDIR/$RELAY_SCRIPT
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
