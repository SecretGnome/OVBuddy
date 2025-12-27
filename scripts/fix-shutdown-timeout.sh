#!/bin/bash

# Script to fix the shutdown timeout issue caused by systemctl blocking
# This updates the fix-bonjour-persistent.sh script to use --no-block

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

echo -e "${BLUE}=== Fixing shutdown timeout issue on ${PI_USER}@${PI_SSH_HOST} ===${NC}"
echo ""

# Deploy the updated script
echo -e "${YELLOW}Deploying updated fix-bonjour-persistent.sh...${NC}"
sshpass -p "$PI_PASSWORD" scp $SSH_OPTS dist/fix-bonjour-persistent.sh "${PI_USER}@${PI_SSH_HOST}:/tmp/" 2>/dev/null
echo "✓ Script deployed"
echo ""

# Install the updated script
echo -e "${YELLOW}Installing updated script...${NC}"
sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
    chmod +x /tmp/fix-bonjour-persistent.sh
    echo '$PI_PASSWORD' | sudo -S cp /tmp/fix-bonjour-persistent.sh /usr/local/bin/fix-bonjour-persistent.sh
    echo '$PI_PASSWORD' | sudo -S chmod +x /usr/local/bin/fix-bonjour-persistent.sh
    echo '✓ Script installed to /usr/local/bin/fix-bonjour-persistent.sh'
" 2>/dev/null
echo ""

# Test that systemctl commands work now
echo -e "${YELLOW}Testing systemctl commands...${NC}"
sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
    echo 'Testing: sudo systemctl is-active ovbuddy'
    echo '$PI_PASSWORD' | sudo -S systemctl is-active ovbuddy 2>&1 || echo '  (service may not be running, that is OK)'
    echo ''
    echo 'Testing: sudo systemctl is-active avahi-daemon'
    echo '$PI_PASSWORD' | sudo -S systemctl is-active avahi-daemon 2>&1
" 2>/dev/null
echo ""

echo -e "${GREEN}=== Fix Complete! ===${NC}"
echo ""
echo -e "${BLUE}What was fixed:${NC}"
echo "  - Updated fix-bonjour-persistent.sh to use --no-block flag"
echo "  - This prevents systemctl commands from blocking/timing out"
echo "  - Web interface shutdown/restart commands should now work"
echo ""
echo -e "${BLUE}To verify:${NC}"
echo "  1. Go to the web interface: http://ovbuddy.local:8080"
echo "  2. Try the 'Shutdown & Clear Display' button"
echo "  3. Try stopping/starting services"
echo "  4. Commands should complete quickly without timeouts"
echo ""
echo -e "${YELLOW}Note: The fix will take full effect after the next reboot${NC}"
echo "You can reboot now with: ssh ${PI_USER}@${PI_SSH_HOST} 'sudo reboot'"
echo ""








