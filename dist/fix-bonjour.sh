#!/bin/bash

# Script to remotely fix Bonjour/mDNS on Raspberry Pi
# Fixes /etc/hosts to not interfere with mDNS

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

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=2"

# Get IP for SSH connection
PI_SSH_HOST="$PI_HOST"
if [[ "$PI_HOST" == *.local ]]; then
    HOSTNAME_SHORT=$(echo "$PI_HOST" | sed 's/\.local$//')
    PI_IP=$(arp -a 2>/dev/null | grep -i "$HOSTNAME_SHORT" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
    if [ -z "$PI_IP" ]; then
        PI_IP=$(ping -c 1 -W 1 "$PI_HOST" 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
    fi
    if [ -n "$PI_IP" ] && [[ "$PI_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        PI_SSH_HOST="$PI_IP"
    else
        echo -e "${RED}Error: Cannot resolve $PI_HOST to IP address${NC}"
        exit 1
    fi
fi

echo -e "${YELLOW}Fixing Bonjour/mDNS on ${PI_USER}@${PI_SSH_HOST}${NC}"
echo ""

# Check current /etc/hosts
echo "Current /etc/hosts entries for ovbuddy:"
sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "grep -i ovbuddy /etc/hosts || echo 'No ovbuddy entries found'" 2>/dev/null
echo ""

# Fix /etc/hosts - remove .local entries that interfere with mDNS
echo "Fixing /etc/hosts (removing .local entries that interfere with mDNS)..."
sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
    sudo sed -i '/\.local/d' /etc/hosts
    echo '✓ Removed .local entries from /etc/hosts'
" 2>/dev/null

echo ""
echo "Restarting avahi-daemon..."
sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
    sudo systemctl reload-or-restart avahi-daemon 2>/dev/null || sudo systemctl try-restart avahi-daemon 2>/dev/null || true
    echo '✓ avahi-daemon restart attempted'
" 2>/dev/null

echo ""
echo -e "${GREEN}Fix complete!${NC}"
echo ""
echo "Now try:"
echo "  - Flush DNS cache on your Mac: sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder"
echo "  - Wait 30-60 seconds for mDNS to propagate"
echo "  - Test: ping ovbuddy.local"
echo "  - Test: ssh pi@ovbuddy.local"

