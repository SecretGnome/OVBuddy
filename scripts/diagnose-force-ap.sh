#!/bin/bash

# Diagnose Force AP Mode Issues
# This script helps identify why Force AP mode might not be working

set -e

# Change to project root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=========================================="
echo "Force AP Mode Diagnostics"
echo -e "==========================================${NC}"
echo ""

# Check if .env file exists
if [ ! -f setup.env ]; then
    echo -e "${RED}Error: setup.env file not found!${NC}"
    echo "Please create a setup.env file with PI_HOST, PI_USER, and PI_PASSWORD"
    exit 1
fi

# Load environment variables
set -a
source setup.env
set +a

# Validate required variables
if [ -z "$PI_HOST" ] || [ -z "$PI_USER" ] || [ -z "$PI_PASSWORD" ]; then
    echo -e "${RED}Error: PI_HOST, PI_USER, and PI_PASSWORD must be set in setup.env file${NC}"
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

echo "Connecting to: ${PI_USER}@${PI_SSH_HOST}"
echo ""

# Function to run remote command
run_remote() {
    sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "$@" 2>&1
}

# Test 1: Check if device is reachable
echo -e "${YELLOW}[1/8] Testing connectivity...${NC}"
if run_remote "echo 'Connected'" | grep -q "Connected"; then
    echo -e "${GREEN}  ✓ Device is reachable${NC}"
else
    echo -e "${RED}  ✗ Cannot connect to device${NC}"
    exit 1
fi
echo ""

# Test 2: Check WiFi manager
echo -e "${YELLOW}[2/8] Detecting WiFi manager...${NC}"
WIFI_MANAGER=$(run_remote "
    if command -v nmcli &> /dev/null; then
        NM_STATUS=\$(nmcli device status 2>/dev/null | grep wlan0 || true)
        if [ -n \"\$NM_STATUS\" ] && ! echo \"\$NM_STATUS\" | grep -q 'unmanaged'; then
            echo 'NetworkManager'
        else
            echo 'wpa_supplicant'
        fi
    else
        echo 'wpa_supplicant'
    fi
")
echo -e "${BLUE}  → WiFi Manager: $WIFI_MANAGER${NC}"
echo ""

# Test 3: Check current WiFi status
echo -e "${YELLOW}[3/8] Checking WiFi connection status...${NC}"
WIFI_STATUS=$(run_remote "iwgetid -r 2>/dev/null || echo 'Not connected'")
if [ "$WIFI_STATUS" != "Not connected" ]; then
    echo -e "${GREEN}  ✓ Connected to: $WIFI_STATUS${NC}"
    WIFI_IP=$(run_remote "ip -4 addr show wlan0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || echo 'No IP'")
    echo -e "${BLUE}  → IP Address: $WIFI_IP${NC}"
else
    echo -e "${YELLOW}  → Not connected to WiFi${NC}"
fi
echo ""

# Test 4: Check configured networks
echo -e "${YELLOW}[4/8] Checking configured WiFi networks...${NC}"
if [ "$WIFI_MANAGER" = "NetworkManager" ]; then
    NETWORKS=$(run_remote "nmcli -t -f NAME,TYPE connection show | grep ':802-11-wireless$' | cut -d: -f1")
    if [ -n "$NETWORKS" ]; then
        echo -e "${BLUE}  → Configured networks:${NC}"
        echo "$NETWORKS" | while read -r network; do
            AUTOCONNECT=$(run_remote "nmcli -t -f connection.autoconnect connection show '$network' | cut -d: -f2")
            if [ "$AUTOCONNECT" = "yes" ]; then
                echo -e "    ${GREEN}✓${NC} $network (auto-connect: ${GREEN}enabled${NC})"
            else
                echo -e "    ${RED}✗${NC} $network (auto-connect: ${RED}disabled${NC})"
            fi
        done
    else
        echo -e "${YELLOW}  → No WiFi networks configured${NC}"
    fi
else
    NETWORKS=$(run_remote "sudo wpa_cli -i wlan0 list_networks | tail -n +2")
    if [ -n "$NETWORKS" ]; then
        echo -e "${BLUE}  → Configured networks:${NC}"
        echo "$NETWORKS" | while read -r line; do
            NETWORK_ID=$(echo "$line" | awk '{print $1}')
            SSID=$(echo "$line" | awk '{print $2}')
            FLAGS=$(echo "$line" | awk '{print $4}')
            if [[ "$FLAGS" == *"DISABLED"* ]]; then
                echo -e "    ${RED}✗${NC} $SSID (ID: $NETWORK_ID) - ${RED}DISABLED${NC}"
            else
                echo -e "    ${GREEN}✓${NC} $SSID (ID: $NETWORK_ID) - ${GREEN}ENABLED${NC}"
            fi
        done
    else
        echo -e "${YELLOW}  → No WiFi networks configured${NC}"
    fi
fi
echo ""

# Test 5: Check if force AP flag exists
echo -e "${YELLOW}[5/8] Checking for force AP flag...${NC}"
if run_remote "[ -f /var/lib/ovbuddy-force-ap ] && echo 'exists' || echo 'not found'" | grep -q "exists"; then
    echo -e "${YELLOW}  ⚠ Force AP flag exists at /var/lib/ovbuddy-force-ap${NC}"
    echo -e "${BLUE}  → This means Force AP mode was requested but may not have activated yet${NC}"
else
    echo -e "${GREEN}  ✓ No force AP flag present${NC}"
fi
echo ""

# Test 6: Check wifi-monitor service
echo -e "${YELLOW}[6/8] Checking wifi-monitor service...${NC}"
SERVICE_STATUS=$(run_remote "systemctl is-active ovbuddy-wifi 2>/dev/null || echo 'inactive'")
if [ "$SERVICE_STATUS" = "active" ]; then
    echo -e "${GREEN}  ✓ ovbuddy-wifi service is running${NC}"
    
    # Check recent logs
    echo -e "${BLUE}  → Recent logs:${NC}"
    run_remote "sudo journalctl -u ovbuddy-wifi -n 5 --no-pager" | sed 's/^/    /'
else
    echo -e "${RED}  ✗ ovbuddy-wifi service is not running${NC}"
fi
echo ""

# Test 7: Check if in AP mode
echo -e "${YELLOW}[7/8] Checking if device is in AP mode...${NC}"
AP_MODE=$(run_remote "sudo iwconfig wlan0 2>/dev/null | grep -q 'Mode:Master' && echo 'yes' || echo 'no'")
if [ "$AP_MODE" = "yes" ]; then
    echo -e "${GREEN}  ✓ Device is in AP mode${NC}"
    AP_IP=$(run_remote "ip -4 addr show wlan0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || echo 'No IP'")
    echo -e "${BLUE}  → AP IP Address: $AP_IP${NC}"
    
    # Check if hostapd is running
    if run_remote "ps aux | grep -v grep | grep -q hostapd"; then
        echo -e "${GREEN}  ✓ hostapd is running${NC}"
    else
        echo -e "${RED}  ✗ hostapd is not running${NC}"
    fi
else
    echo -e "${BLUE}  → Device is in client mode${NC}"
fi
echo ""

# Test 8: Summary and recommendations
echo -e "${YELLOW}[8/8] Analysis and Recommendations${NC}"
echo ""

if [ "$WIFI_STATUS" != "Not connected" ] && [ "$AP_MODE" = "no" ]; then
    echo -e "${GREEN}✓ Device is connected to WiFi and functioning normally${NC}"
    echo ""
    echo -e "${BLUE}If you want to test Force AP mode:${NC}"
    echo "  1. Run: ./scripts/force-ap-mode.sh"
    echo "  2. Wait for device to reboot (~60 seconds)"
    echo "  3. Look for WiFi network (check config.json for SSID)"
    echo "  4. Connect and access http://192.168.4.1:8080"
elif [ "$AP_MODE" = "yes" ]; then
    echo -e "${GREEN}✓ Device is in AP mode${NC}"
    echo ""
    echo -e "${BLUE}To return to client mode:${NC}"
    echo "  1. Connect to the AP"
    echo "  2. Open http://192.168.4.1:8080"
    echo "  3. Configure WiFi settings"
    echo "  4. Device will automatically reconnect"
else
    echo -e "${YELLOW}⚠ Device is not connected to WiFi${NC}"
    echo ""
    
    # Check if networks are disabled
    if [ "$WIFI_MANAGER" = "NetworkManager" ]; then
        DISABLED_COUNT=$(echo "$NETWORKS" | wc -l)
        if [ "$DISABLED_COUNT" -gt 0 ]; then
            echo -e "${RED}Issue detected: WiFi networks have auto-connect disabled${NC}"
            echo ""
            echo -e "${BLUE}This is likely why Force AP mode isn't working properly.${NC}"
            echo "The networks are disabled but the device hasn't entered AP mode yet."
            echo ""
            echo -e "${YELLOW}Possible causes:${NC}"
            echo "  1. wifi-monitor service not running"
            echo "  2. Force AP flag was removed but AP mode not activated"
            echo "  3. Device rebooted but networks reconnected before wifi-monitor started"
            echo ""
            echo -e "${BLUE}Recommended fix:${NC}"
            echo "  1. Restart wifi-monitor service:"
            echo "     ssh pi@$PI_HOST 'sudo systemctl restart ovbuddy-wifi'"
            echo "  2. Or manually re-enable networks:"
            echo "     ssh pi@$PI_HOST 'nmcli connection modify <network-name> connection.autoconnect yes'"
        fi
    fi
    
    echo -e "${BLUE}To force AP mode:${NC}"
    echo "  ./scripts/force-ap-mode.sh"
fi

echo ""
echo -e "${BLUE}=========================================="
echo "Diagnostics Complete"
echo -e "==========================================${NC}"

