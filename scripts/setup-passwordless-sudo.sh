#!/bin/bash

# Script to setup passwordless sudo for OVBuddy on Raspberry Pi
# This allows the service to perform necessary system operations without password prompts

set -e

# Change to project root directory (parent of scripts/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Setting up passwordless sudo for OVBuddy${NC}"
echo ""

# Check if .env file exists
if [ ! -f .env ]; then
    echo -e "${RED}Error: .env file not found!${NC}"
    echo "Please create a .env file with PI_HOST, PI_USER, and PI_PASSWORD"
    exit 1
fi

# Load environment variables from .env file
set -a
source .env
set +a

# Validate required variables
if [ -z "$PI_HOST" ] || [ -z "$PI_USER" ] || [ -z "$PI_PASSWORD" ]; then
    echo -e "${RED}Error: PI_HOST, PI_USER, and PI_PASSWORD must be set in .env file${NC}"
    exit 1
fi

SSH_OPTS="-o StrictHostKeyChecking=no -o PreferredAuthentications=password -o PubkeyAuthentication=no"

# Try to resolve IP if hostname is used
PI_SSH_HOST="$PI_HOST"
if [[ "$PI_HOST" == *.local ]]; then
    HOSTNAME_SHORT=$(echo "$PI_HOST" | sed 's/\.local$//')
    PI_IP=$(arp -a 2>/dev/null | grep -i "$HOSTNAME_SHORT" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
    
    if [ -z "$PI_IP" ]; then
        PI_IP=$(ping -c 1 -W 1 "$PI_HOST" 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
    fi
    
    if [ -n "$PI_IP" ] && [[ "$PI_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${YELLOW}Using IP address $PI_IP for SSH connection${NC}"
        PI_SSH_HOST="$PI_IP"
    fi
fi

echo "Connecting to ${PI_USER}@${PI_SSH_HOST}..."
echo ""

# Create sudoers configuration for passwordless sudo
# Only grant permissions for specific commands needed by OVBuddy
SUDOERS_CONTENT="# OVBuddy passwordless sudo configuration
# Allows OVBuddy service to perform necessary system operations

# Allow systemctl commands for ovbuddy services
${PI_USER} ALL=(ALL) NOPASSWD: /bin/systemctl start ovbuddy
${PI_USER} ALL=(ALL) NOPASSWD: /bin/systemctl stop ovbuddy
${PI_USER} ALL=(ALL) NOPASSWD: /bin/systemctl restart ovbuddy
${PI_USER} ALL=(ALL) NOPASSWD: /bin/systemctl status ovbuddy
${PI_USER} ALL=(ALL) NOPASSWD: /bin/systemctl enable ovbuddy
${PI_USER} ALL=(ALL) NOPASSWD: /bin/systemctl disable ovbuddy
${PI_USER} ALL=(ALL) NOPASSWD: /bin/systemctl start ovbuddy-web
${PI_USER} ALL=(ALL) NOPASSWD: /bin/systemctl stop ovbuddy-web
${PI_USER} ALL=(ALL) NOPASSWD: /bin/systemctl restart ovbuddy-web
${PI_USER} ALL=(ALL) NOPASSWD: /bin/systemctl status ovbuddy-web
${PI_USER} ALL=(ALL) NOPASSWD: /bin/systemctl enable ovbuddy-web
${PI_USER} ALL=(ALL) NOPASSWD: /bin/systemctl disable ovbuddy-web
${PI_USER} ALL=(ALL) NOPASSWD: /bin/systemctl daemon-reload

# Allow network configuration commands
${PI_USER} ALL=(ALL) NOPASSWD: /sbin/iwlist * scan
${PI_USER} ALL=(ALL) NOPASSWD: /sbin/wpa_cli *
${PI_USER} ALL=(ALL) NOPASSWD: /usr/bin/wpa_cli *
${PI_USER} ALL=(ALL) NOPASSWD: /bin/systemctl restart wpa_supplicant
${PI_USER} ALL=(ALL) NOPASSWD: /bin/systemctl restart dhcpcd
${PI_USER} ALL=(ALL) NOPASSWD: /sbin/dhclient *
${PI_USER} ALL=(ALL) NOPASSWD: /usr/sbin/dhclient *
${PI_USER} ALL=(ALL) NOPASSWD: /usr/bin/tee /etc/wpa_supplicant/wpa_supplicant.conf
${PI_USER} ALL=(ALL) NOPASSWD: /usr/bin/tee /etc/wpa_supplicant/wpa_supplicant-wlan0.conf
${PI_USER} ALL=(ALL) NOPASSWD: /bin/cat /etc/wpa_supplicant/wpa_supplicant.conf
${PI_USER} ALL=(ALL) NOPASSWD: /bin/cat /etc/wpa_supplicant/wpa_supplicant-wlan0.conf
${PI_USER} ALL=(ALL) NOPASSWD: /usr/bin/test -f /etc/wpa_supplicant/*
${PI_USER} ALL=(ALL) NOPASSWD: /bin/mkdir -p /etc/wpa_supplicant

# Allow Bonjour/mDNS configuration
${PI_USER} ALL=(ALL) NOPASSWD: /bin/systemctl * avahi-daemon
${PI_USER} ALL=(ALL) NOPASSWD: /bin/sed -i * /etc/hosts

# Allow viewing logs
${PI_USER} ALL=(ALL) NOPASSWD: /bin/journalctl *
"

# Upload and install sudoers configuration
echo "Installing passwordless sudo configuration..."
echo "$SUDOERS_CONTENT" | sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
    # Create temporary file
    cat > /tmp/ovbuddy-sudoers
    
    # Validate sudoers syntax
    if sudo visudo -c -f /tmp/ovbuddy-sudoers; then
        # Install the file
        sudo cp /tmp/ovbuddy-sudoers /etc/sudoers.d/ovbuddy
        sudo chmod 0440 /etc/sudoers.d/ovbuddy
        sudo chown root:root /etc/sudoers.d/ovbuddy
        rm /tmp/ovbuddy-sudoers
        echo 'SUCCESS'
    else
        echo 'FAILED'
        rm /tmp/ovbuddy-sudoers
        exit 1
    fi
"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Passwordless sudo configured successfully!${NC}"
    echo ""
    echo "The following commands can now be run without password:"
    echo "  - systemctl commands for ovbuddy services"
    echo "  - WiFi scanning and configuration"
    echo "  - Bonjour/mDNS configuration"
    echo "  - Viewing system logs"
    echo ""
    echo -e "${GREEN}Note: This is a limited passwordless sudo configuration for security.${NC}"
    echo "Only specific OVBuddy-related commands are allowed without password."
else
    echo -e "${RED}✗ Failed to configure passwordless sudo${NC}"
    exit 1
fi

