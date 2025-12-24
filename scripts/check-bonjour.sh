#!/bin/bash

# Script to remotely check Bonjour/mDNS setup on Raspberry Pi
# Reads credentials from .env file

# Change to project root directory (parent of scripts/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if .env file exists
if [ ! -f .env ]; then
    echo -e "${RED}Error: .env file not found!${NC}"
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

SSH_OPTS="-o StrictHostKeyChecking=no"

# Try to resolve IP if hostname is used
PI_SSH_HOST="$PI_HOST"
if [[ "$PI_HOST" == *.local ]]; then
    # Try multiple methods to get IP
    # Method 1: arp cache (remove .local from hostname)
    HOSTNAME_SHORT=$(echo "$PI_HOST" | sed 's/\.local$//')
    PI_IP=$(arp -a 2>/dev/null | grep -i "$HOSTNAME_SHORT" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
    
    # Method 2: ping (if arp didn't work)
    if [ -z "$PI_IP" ]; then
        PI_IP=$(ping -c 1 -W 1 "$PI_HOST" 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
    fi
    
    if [ -n "$PI_IP" ] && [[ "$PI_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${YELLOW}Using IP address $PI_IP for SSH connection (hostname not resolving)${NC}"
        PI_SSH_HOST="$PI_IP"
    else
        echo -e "${RED}Error: Cannot resolve $PI_HOST to IP address${NC}"
        echo "Please update .env with PI_HOST=<ip-address> temporarily"
        echo "Or manually set: PI_SSH_HOST=192.168.1.167"
        exit 1
    fi
fi

echo -e "${YELLOW}Checking Bonjour/mDNS setup on ${PI_USER}@${PI_HOST}${NC}"
echo ""

# Check hostname
echo "1. Checking hostname:"
HOSTNAME=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "hostname" 2>/dev/null)
echo "   Hostname: $HOSTNAME"
if [ "$HOSTNAME" == "ovbuddy" ]; then
    echo -e "   ${GREEN}✓ Hostname is correct${NC}"
else
    echo -e "   ${RED}✗ Hostname should be 'ovbuddy' but is '$HOSTNAME'${NC}"
    echo "   To fix: sudo hostnamectl set-hostname ovbuddy"
fi
echo ""

# Check avahi-daemon
echo "2. Checking avahi-daemon service:"
AVAHI_STATUS=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "systemctl is-active avahi-daemon 2>/dev/null || echo 'inactive'" 2>/dev/null)
if [ "$AVAHI_STATUS" == "active" ]; then
    echo -e "   ${GREEN}✓ avahi-daemon is running${NC}"
else
    echo -e "   ${RED}✗ avahi-daemon is not running (status: $AVAHI_STATUS)${NC}"
    echo "   To fix: sudo systemctl start avahi-daemon && sudo systemctl enable avahi-daemon"
fi
echo ""

# Check IP address
echo "3. Checking IP address:"
IP_ADDR=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "hostname -I | awk '{print \$1}'" 2>/dev/null)
echo "   IP Address: $IP_ADDR"
echo ""

# Check if hostname resolves locally
echo "4. Testing hostname resolution on Pi:"
RESOLVE_TEST=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "getent hosts ${HOSTNAME}.local 2>/dev/null | head -1 || echo 'not found'" 2>/dev/null)
if [[ "$RESOLVE_TEST" == *"not found"* ]]; then
    echo -e "   ${YELLOW}⚠ Hostname does not resolve locally on Pi${NC}"
else
    echo -e "   ${GREEN}✓ Hostname resolves: $RESOLVE_TEST${NC}"
fi
echo ""

# Summary
echo "Summary:"
if [ "$HOSTNAME" == "ovbuddy" ] && [ "$AVAHI_STATUS" == "active" ]; then
    echo -e "${GREEN}✓ Bonjour should work. If it doesn't, try:${NC}"
    echo "   - Restart avahi-daemon: sudo systemctl restart avahi-daemon"
    echo "   - Wait a few minutes for mDNS to propagate"
    echo "   - Flush DNS cache on your Mac: sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder"
else
    echo -e "${YELLOW}⚠ Bonjour setup needs attention.${NC}"
    if [ "$HOSTNAME" != "ovbuddy" ]; then
        echo "   - Set hostname: sudo hostnamectl set-hostname ovbuddy"
        echo "   - Reboot the Pi"
    fi
    if [ "$AVAHI_STATUS" != "active" ]; then
        echo "   - Start avahi-daemon: sudo systemctl start avahi-daemon && sudo systemctl enable avahi-daemon"
    fi
fi

