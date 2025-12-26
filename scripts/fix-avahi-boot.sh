#!/bin/bash

# Script to fix avahi-daemon not starting on boot
# This deploys the fix to the Raspberry Pi

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

echo -e "${BLUE}=== Fixing avahi-daemon boot issue on ${PI_USER}@${PI_SSH_HOST} ===${NC}"
echo ""

# Check current avahi-daemon status
echo -e "${YELLOW}Checking current avahi-daemon status...${NC}"
sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
    echo 'Enabled status:'
    systemctl is-enabled avahi-daemon 2>&1 || echo '  ✗ NOT enabled'
    echo ''
    echo 'Active status:'
    systemctl is-active avahi-daemon 2>&1 || echo '  ✗ NOT running'
" 2>/dev/null
echo ""

# Deploy the ensure-avahi-enabled script
echo -e "${YELLOW}Deploying ensure-avahi-enabled.sh script...${NC}"
sshpass -p "$PI_PASSWORD" scp $SSH_OPTS dist/ensure-avahi-enabled.sh "${PI_USER}@${PI_SSH_HOST}:/tmp/" 2>/dev/null
echo "✓ Script deployed"
echo ""

# Run the script on the Pi
echo -e "${YELLOW}Running ensure-avahi-enabled.sh on Pi...${NC}"
sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
    chmod +x /tmp/ensure-avahi-enabled.sh
    echo '$PI_PASSWORD' | sudo -S /tmp/ensure-avahi-enabled.sh
" 2>/dev/null
echo ""

# Re-deploy and reinstall the fix-bonjour service with updated script
echo -e "${YELLOW}Updating fix-bonjour service...${NC}"
sshpass -p "$PI_PASSWORD" scp $SSH_OPTS dist/fix-bonjour.service dist/fix-bonjour-persistent.sh dist/install-fix-bonjour.sh "${PI_USER}@${PI_SSH_HOST}:/tmp/" 2>/dev/null
echo "✓ Files deployed"
echo ""

echo -e "${YELLOW}Installing updated fix-bonjour service...${NC}"
sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
    cd /tmp
    chmod +x install-fix-bonjour.sh fix-bonjour-persistent.sh
    echo '$PI_PASSWORD' | sudo -S ./install-fix-bonjour.sh
" 2>/dev/null
echo ""

# Final status check
echo -e "${YELLOW}Final status check...${NC}"
sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
    echo 'avahi-daemon status:'
    systemctl is-enabled avahi-daemon && echo '  ✓ Enabled' || echo '  ✗ NOT enabled'
    systemctl is-active avahi-daemon && echo '  ✓ Running' || echo '  ✗ NOT running'
    echo ''
    echo 'fix-bonjour service status:'
    systemctl is-enabled fix-bonjour && echo '  ✓ Enabled' || echo '  ✗ NOT enabled'
" 2>/dev/null
echo ""

echo -e "${GREEN}=== Fix Complete! ===${NC}"
echo ""
echo -e "${BLUE}What was fixed:${NC}"
echo "  1. Ensured avahi-daemon is installed"
echo "  2. Unmasked avahi-daemon (in case it was masked)"
echo "  3. Enabled avahi-daemon to start on boot"
echo "  4. Started avahi-daemon if it wasn't running"
echo "  5. Updated fix-bonjour service with better boot handling"
echo ""
echo -e "${BLUE}To verify the fix:${NC}"
echo "  1. Reboot the Pi: ssh ${PI_USER}@${PI_SSH_HOST} 'sudo reboot'"
echo "  2. Wait 60 seconds for it to boot"
echo "  3. Test mDNS: ping ovbuddy.local"
echo "  4. Check logs: ssh ${PI_USER}@ovbuddy.local 'sudo journalctl -u avahi-daemon -u fix-bonjour -n 50'"
echo ""





