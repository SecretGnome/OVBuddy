#!/bin/bash

# Remote script to force OVBuddy into Access Point mode
# This script connects to the Raspberry Pi and forces AP mode

set -e

# Change to project root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if .env file exists
if [ ! -f .env ]; then
    echo -e "${RED}Error: .env file not found!${NC}"
    echo "Please create a .env file with PI_HOST, PI_USER, and PI_PASSWORD"
    exit 1
fi

# Load environment variables
set -a
source .env
set +a

# Validate required variables
if [ -z "$PI_HOST" ] || [ -z "$PI_USER" ] || [ -z "$PI_PASSWORD" ]; then
    echo -e "${RED}Error: PI_HOST, PI_USER, and PI_PASSWORD must be set in .env file${NC}"
    exit 1
fi

# Check if sshpass is installed
if ! command -v sshpass &> /dev/null; then
    echo -e "${RED}Error: sshpass is required${NC}"
    echo "Install it with: brew install hudochenkov/sshpass/sshpass"
    exit 1
fi

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10"

# Try to resolve IP if hostname is used
PI_SSH_HOST="$PI_HOST"
if [[ "$PI_HOST" == *.local ]]; then
    HOSTNAME_SHORT=$(echo "$PI_HOST" | sed 's/\.local$//')
    PI_IP=$(arp -a 2>/dev/null | grep -i "$HOSTNAME_SHORT" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
    if [ -z "$PI_IP" ]; then
        PI_IP=$(ping -c 1 -W 1 "$PI_HOST" 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
    fi
    if [ -n "$PI_IP" ] && [[ "$PI_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        PI_SSH_HOST="$PI_IP"
    fi
fi

echo -e "${YELLOW}=========================================="
echo "Force Access Point Mode"
echo -e "==========================================${NC}"
echo ""
echo "Connecting to: ${PI_USER}@${PI_SSH_HOST}"
echo ""

# Confirm action
echo -e "${YELLOW}WARNING: This will:${NC}"
echo "  1. Clear all WiFi configurations on the device"
echo "  2. Reboot the device"
echo "  3. Device will enter AP mode after reboot"
echo ""
echo -e "${YELLOW}You will lose connection to the device!${NC}"
echo ""
read -p "Are you sure you want to continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "Clearing WiFi configuration and rebooting device..."

# Run the force-ap-mode script on the Pi (it will reboot)
# Use nohup to prevent hanging when device reboots
sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "nohup sudo /home/pi/ovbuddy/force-ap-mode.sh > /dev/null 2>&1 &" 2>&1

echo ""
echo -e "${GREEN}=========================================="
echo "Device is Rebooting!"
echo -e "==========================================${NC}"
echo ""
echo "WiFi configuration has been cleared."
echo "The device is rebooting and will enter Access Point mode."
echo ""
echo "Wait about 60 seconds, then:"
echo ""
echo "1. Look for WiFi network (check config.json for SSID, default: OVBuddy)"
echo "2. Connect to the AP"
echo "3. Open web interface: http://192.168.4.1:8080"
echo "4. Configure WiFi settings"
echo ""
echo "WiFi configuration backup saved on device at:"
echo "  /home/pi/ovbuddy/wifi-backup/wpa_supplicant.conf.[timestamp]"
echo ""

