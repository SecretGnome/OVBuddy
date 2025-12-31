#!/bin/bash

# Test SSH connection to Raspberry Pi
# This script helps diagnose SSH connection issues

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          OVBuddy SSH Connection Test                       ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Load configuration from setup.env
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SETUP_ENV="$PROJECT_ROOT/setup.env"

if [[ -f "$SETUP_ENV" ]]; then
    echo -e "${GREEN}Loading configuration from setup.env...${NC}"
    source "$SETUP_ENV"
    echo ""
else
    echo -e "${YELLOW}setup.env not found. Please enter connection details:${NC}"
    read -p "Hostname (e.g., ovbuddy.local): " HOSTNAME
    read -p "Username (default: pi): " USERNAME
    USERNAME=${USERNAME:-pi}
    read -sp "Password: " USER_PASSWORD
    echo ""
    echo ""
fi

# Set defaults
HOSTNAME=${HOSTNAME:-ovbuddy}
USERNAME=${USERNAME:-pi}

# Add .local if not present
if [[ ! "$HOSTNAME" =~ \.local$ ]]; then
    HOSTNAME="${HOSTNAME}.local"
fi

echo -e "${YELLOW}Testing connection to ${USERNAME}@${HOSTNAME}${NC}"
echo ""

# Test 1: Ping test
echo -e "${BLUE}[1/5] Testing network connectivity (ping)...${NC}"
if ping -c 3 -W 2 "$HOSTNAME" > /dev/null 2>&1; then
    IP=$(ping -c 1 "$HOSTNAME" 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
    echo -e "${GREEN}  ✓ Host is reachable at $IP${NC}"
else
    echo -e "${RED}  ✗ Cannot reach host${NC}"
    echo -e "${YELLOW}  Troubleshooting tips:${NC}"
    echo "    - Ensure the Pi is powered on"
    echo "    - Check that the Pi is connected to WiFi"
    echo "    - Verify the hostname is correct"
    echo "    - Try using the IP address directly"
    exit 1
fi
echo ""

# Test 2: mDNS resolution
echo -e "${BLUE}[2/5] Testing mDNS resolution...${NC}"
if host "$HOSTNAME" > /dev/null 2>&1; then
    echo -e "${GREEN}  ✓ mDNS resolution working${NC}"
elif dns-sd -G v4 "$HOSTNAME" > /dev/null 2>&1; then
    echo -e "${GREEN}  ✓ mDNS resolution working (via dns-sd)${NC}"
else
    echo -e "${YELLOW}  ⚠ mDNS resolution may not be working${NC}"
    echo -e "${YELLOW}    Using IP address: $IP${NC}"
    HOSTNAME="$IP"
fi
echo ""

# Test 3: SSH port check
echo -e "${BLUE}[3/5] Testing SSH port (22)...${NC}"
if nc -z -w 5 "$HOSTNAME" 22 2>/dev/null; then
    echo -e "${GREEN}  ✓ SSH port is open${NC}"
else
    echo -e "${RED}  ✗ SSH port is not accessible${NC}"
    echo -e "${YELLOW}  Troubleshooting tips:${NC}"
    echo "    - Ensure SSH was enabled during SD card setup"
    echo "    - Check if the Pi has finished booting (first boot takes 2-3 minutes)"
    echo "    - Verify firewall settings"
    exit 1
fi
echo ""

# Test 4: SSH connection without password
echo -e "${BLUE}[4/5] Testing SSH connection (without password)...${NC}"
if ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no "${USERNAME}@${HOSTNAME}" "echo 'success'" > /dev/null 2>&1; then
    echo -e "${GREEN}  ✓ SSH key authentication working${NC}"
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  SSH Connection Test: SUCCESS (using SSH keys)             ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    exit 0
else
    echo -e "${YELLOW}  ⚠ SSH key authentication not configured${NC}"
    echo -e "${YELLOW}    Will try password authentication...${NC}"
fi
echo ""

# Test 5: SSH connection with password
echo -e "${BLUE}[5/5] Testing SSH connection (with password)...${NC}"

# Check if sshpass is installed
if ! command -v sshpass &> /dev/null; then
    echo -e "${RED}  ✗ sshpass is not installed${NC}"
    echo ""
    echo "To test password authentication, install sshpass:"
    echo "  brew install hudochenkov/sshpass/sshpass"
    echo ""
    echo "Or try connecting manually:"
    echo "  ssh ${USERNAME}@${HOSTNAME}"
    exit 1
fi

# If password is not set, prompt for it
if [[ -z "$USER_PASSWORD" ]]; then
    read -sp "Enter password for ${USERNAME}@${HOSTNAME}: " USER_PASSWORD
    echo ""
    echo ""
fi

# Try to connect with password
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o PreferredAuthentications=password -o PubkeyAuthentication=no"

echo -e "${YELLOW}  Attempting to connect with password...${NC}"
SSH_RESULT=$(sshpass -p "$USER_PASSWORD" ssh $SSH_OPTS "${USERNAME}@${HOSTNAME}" "echo 'SSH_SUCCESS' && whoami && uname -a" 2>&1)
SSH_EXIT_CODE=$?

if [ $SSH_EXIT_CODE -eq 0 ] && echo "$SSH_RESULT" | grep -q "SSH_SUCCESS"; then
    echo -e "${GREEN}  ✓ SSH password authentication working${NC}"
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  SSH Connection Test: SUCCESS                              ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Connected as: $(echo "$SSH_RESULT" | grep -v "SSH_SUCCESS" | head -1)"
    echo "System: $(echo "$SSH_RESULT" | tail -1)"
    echo ""
    echo "You can now run the deployment script:"
    echo "  cd scripts"
    echo "  ./deploy.sh"
else
    echo -e "${RED}  ✗ SSH password authentication failed${NC}"
    echo ""
    echo -e "${YELLOW}Error details:${NC}"
    echo "$SSH_RESULT" | head -5
    echo ""
    echo -e "${YELLOW}Troubleshooting tips:${NC}"
    echo "  1. Verify the password is correct"
    echo "  2. Check if the user account was created properly"
    echo "  3. Try connecting manually to see the exact error:"
    echo "     ssh ${USERNAME}@${HOSTNAME}"
    echo ""
    echo "  4. If you just set up the SD card:"
    echo "     - Ensure the Pi has completed its first boot"
    echo "     - First boot takes 2-3 minutes and includes an automatic reboot"
    echo "     - Wait 30 seconds after the reboot, then try again"
    echo ""
    echo "  5. If the password is definitely correct:"
    echo "     - The password hash may not have been set correctly"
    echo "     - You may need to recreate the SD card"
    echo "     - Or connect a monitor/keyboard to reset the password"
    exit 1
fi








