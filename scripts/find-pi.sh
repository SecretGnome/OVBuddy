#!/bin/bash

# Script to find Raspberry Pi on the local network
# Helps locate the Pi when .local hostname resolution isn't working

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          OVBuddy Pi Finder                                 ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SETUP_ENV="$PROJECT_ROOT/setup.env"

if [[ -f "$SETUP_ENV" ]]; then
    source "$SETUP_ENV"
    HOSTNAME=${HOSTNAME:-ovbuddy}
    USERNAME=${USERNAME:-pi}
else
    HOSTNAME="ovbuddy"
    USERNAME="pi"
fi

echo -e "${YELLOW}Looking for Raspberry Pi (hostname: $HOSTNAME)...${NC}"
echo ""

# Method 1: Try .local hostname first
echo -e "${BLUE}[1/4] Trying mDNS (.local) hostname...${NC}"
if ping -c 1 -W 1 "$HOSTNAME.local" &> /dev/null; then
    IP=$(ping -c 1 "$HOSTNAME.local" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
    echo -e "${GREEN}✓ Found via mDNS: $HOSTNAME.local ($IP)${NC}"
    echo ""
    echo -e "${GREEN}You can connect with:${NC}"
    echo "  ssh ${USERNAME}@$HOSTNAME.local"
    exit 0
else
    echo -e "${YELLOW}  Not found via mDNS${NC}"
fi
echo ""

# Method 2: Try dns-sd (built-in macOS)
echo -e "${BLUE}[2/4] Scanning for SSH services via Bonjour...${NC}"
echo -e "${YELLOW}  (This will take 5 seconds)${NC}"
# macOS doesn't ship with GNU timeout; do our own 5s capture.
DNSSD_TMP=$(mktemp)
dns-sd -B _ssh._tcp local. >"$DNSSD_TMP" 2>/dev/null &
DNSSD_PID=$!
sleep 5
kill "$DNSSD_PID" 2>/dev/null || true
wait "$DNSSD_PID" 2>/dev/null || true
DNSSD_OUTPUT=$(cat "$DNSSD_TMP" 2>/dev/null || true)
rm -f "$DNSSD_TMP" || true
if echo "$DNSSD_OUTPUT" | grep -q "$HOSTNAME"; then
    echo -e "${GREEN}✓ Found SSH service for $HOSTNAME${NC}"
    echo ""
    echo "Resolving IP address..."
    # Try to resolve the IP
    if IP=$(dns-sd -G v4 "$HOSTNAME.local" 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1); then
        echo -e "${GREEN}✓ IP Address: $IP${NC}"
        echo ""
        echo -e "${GREEN}You can connect with:${NC}"
        echo "  ssh ${USERNAME}@$IP"
        echo "  or"
        echo "  ssh ${USERNAME}@$HOSTNAME.local"
        exit 0
    fi
else
    echo -e "${YELLOW}  Not found via Bonjour${NC}"
fi
echo ""

# Method 3: Built-in scan (no extra installs): ping sweep + ARP table + check SSH port
echo -e "${BLUE}[3/4] Scanning local subnet (built-in tools)...${NC}"
DEFAULT_IF=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}' | head -1)
LOCAL_IP=$(ipconfig getifaddr "$DEFAULT_IF" 2>/dev/null || ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)
if [[ -n "$LOCAL_IP" ]]; then
    NETWORK=$(echo "$LOCAL_IP" | cut -d. -f1-3)
    echo -e "${YELLOW}  Probing ${NETWORK}.0/24 (fast ping sweep)...${NC}"
    # Prime ARP cache quickly; ignore failures
    seq 1 254 | xargs -P 64 -I{} sh -c "ping -c 1 -W 1 ${NETWORK}.{} >/dev/null 2>&1 || true"
    # Raspberry Pi MAC address prefixes: b8:27:eb, dc:a6:32, e4:5f:01 (plus some newer: d8:3a:dd)
    CANDIDATES=$(arp -a 2>/dev/null | grep -iE " at (b8:27:eb|dc:a6:32|e4:5f:01|d8:3a:dd)" | sed -E 's/.*\(([0-9.]+)\).*/\1/' | sort -u)
    if [[ -n "$CANDIDATES" ]]; then
        echo -e "${GREEN}✓ Found Raspberry Pi-like MAC(s) in ARP cache:${NC}"
        echo "$CANDIDATES" | sed 's/^/  - /'
        echo ""
        echo -e "${YELLOW}  Checking which ones have SSH (port 22) open...${NC}"
        FOUND_IP=""
        for ip in $CANDIDATES; do
            if nc -G 1 -z "$ip" 22 >/dev/null 2>&1; then
                FOUND_IP="$ip"
                break
            fi
        done
        if [[ -n "$FOUND_IP" ]]; then
            echo -e "${GREEN}✓ SSH is reachable at: $FOUND_IP${NC}"
            echo ""
            echo -e "${GREEN}You can connect with:${NC}"
            echo "  ssh ${USERNAME}@$FOUND_IP"
            exit 0
        else
            echo -e "${YELLOW}  Found Pi-like devices, but SSH port 22 not open yet.${NC}"
        fi
    else
        echo -e "${YELLOW}  No Raspberry Pi MACs found in ARP cache.${NC}"
    fi
else
    echo -e "${YELLOW}  Could not determine local IP/interface to scan.${NC}"
fi
echo ""

# Method 4: Try nmap if available
echo -e "${BLUE}[4/4] Scanning network with nmap...${NC}"
if command -v nmap &> /dev/null; then
    echo -e "${YELLOW}  (This will take 10-30 seconds)${NC}"
    # Get the local network range
    LOCAL_IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "192.168.1.1")
    NETWORK=$(echo "$LOCAL_IP" | cut -d. -f1-3)
    
    NMAP_OUTPUT=$(nmap -sn "$NETWORK.0/24" 2>/dev/null | grep -B 2 -i "raspberry" || true)
    if [ -n "$NMAP_OUTPUT" ]; then
        echo -e "${GREEN}✓ Found Raspberry Pi:${NC}"
        echo "$NMAP_OUTPUT"
        IP=$(echo "$NMAP_OUTPUT" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
        echo ""
        echo -e "${GREEN}You can connect with:${NC}"
        echo "  ssh ${USERNAME}@$IP"
        exit 0
    else
        echo -e "${YELLOW}  No Raspberry Pi devices found${NC}"
    fi
else
    echo -e "${YELLOW}  nmap not installed. Install with: brew install nmap${NC}"
fi
echo ""

# If we get here, we couldn't find the Pi
echo -e "${RED}═══════════════════════════════════════════════════════════${NC}"
echo -e "${RED}  Could not automatically find the Raspberry Pi${NC}"
echo -e "${RED}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}Possible issues:${NC}"
echo "  1. The Pi hasn't finished booting (wait 3-4 minutes from power-on)"
echo "  2. WiFi connection failed (check SSID/password in setup.env)"
echo "  3. WiFi network is 5GHz only (Pi Zero W only supports 2.4GHz)"
echo "  4. Wrong WiFi country code in setup.env"
echo "  5. Your Mac and Pi are on different networks"
echo ""
echo -e "${YELLOW}Manual steps:${NC}"
echo "  1. Check your router's admin page for a device named '$HOSTNAME'"
echo "  2. Look at the Pi's LEDs:"
echo "     - Red LED on, green LED blinking: Normal boot"
echo "     - Only red LED: Not booting (SD card issue)"
echo "     - Both LEDs flashing: Under-voltage (bad power supply)"
echo "  3. Recreate the SD card using Raspberry Pi Imager (see doc/SD_CARD_SETUP.md)"
echo ""
echo -e "${YELLOW}For more help, see:${NC}"
echo "  doc/SD_CARD_TROUBLESHOOTING.md"
echo ""


