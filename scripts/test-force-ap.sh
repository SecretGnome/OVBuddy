#!/bin/bash

# Test script to diagnose Force AP Mode issues
# This script checks if all required permissions are in place

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

# Check if .env file exists
if [ ! -f .env ]; then
    echo -e "${RED}Error: .env file not found!${NC}"
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
    exit 1
fi

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10"

# Try to resolve IP
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

echo -e "${BLUE}=========================================="
echo "Force AP Mode - Diagnostic Test"
echo -e "==========================================${NC}"
echo ""
echo "Connecting to: ${PI_USER}@${PI_SSH_HOST}"
echo ""

# Function to run remote command
run_remote() {
    sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "$1" 2>&1
}

# Function to test sudo command
test_sudo() {
    local cmd="$1"
    local desc="$2"
    
    echo -n "Testing: $desc... "
    
    result=$(run_remote "sudo -n $cmd 2>&1")
    exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}✓ OK${NC}"
        return 0
    else
        echo -e "${RED}✗ FAILED${NC}"
        echo "  Error: $result"
        return 1
    fi
}

# Test 1: Check if script exists
echo -e "${YELLOW}=== Checking Files ===${NC}"
echo ""

echo -n "force-ap-mode.sh exists... "
if run_remote "[ -f /home/pi/ovbuddy/force-ap-mode.sh ]" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ OK${NC}"
else
    echo -e "${RED}✗ NOT FOUND${NC}"
    echo "  Run: ./scripts/deploy.sh"
fi

echo -n "force-ap-mode.sh is executable... "
if run_remote "[ -x /home/pi/ovbuddy/force-ap-mode.sh ]" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ OK${NC}"
else
    echo -e "${RED}✗ NOT EXECUTABLE${NC}"
    echo "  Run: ssh ${PI_USER}@${PI_SSH_HOST} 'chmod +x /home/pi/ovbuddy/force-ap-mode.sh'"
fi

echo ""

# Test 2: Check passwordless sudo
echo -e "${YELLOW}=== Checking Passwordless Sudo ===${NC}"
echo ""

echo -n "General sudo access... "
if run_remote "sudo -n echo test" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ OK${NC}"
else
    echo -e "${RED}✗ FAILED${NC}"
    echo "  Run: ./scripts/setup-passwordless-sudo.sh"
fi

test_sudo "bash /home/pi/ovbuddy/force-ap-mode.sh --help" "Run force-ap-mode.sh" || true

echo ""

# Test 3: Check API endpoint
echo -e "${YELLOW}=== Checking API Endpoint ===${NC}"
echo ""

echo -n "Web service running... "
if run_remote "systemctl is-active ovbuddy-web" | grep -q "active"; then
    echo -e "${GREEN}✓ OK${NC}"
else
    echo -e "${RED}✗ NOT RUNNING${NC}"
    echo "  Run: ssh ${PI_USER}@${PI_SSH_HOST} 'sudo systemctl start ovbuddy-web'"
fi

echo -n "API endpoint accessible... "
response=$(run_remote "curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/api/config" 2>&1)
if [ "$response" = "200" ]; then
    echo -e "${GREEN}✓ OK${NC}"
else
    echo -e "${RED}✗ FAILED (HTTP $response)${NC}"
fi

echo ""

# Test 4: Check WiFi configuration
echo -e "${YELLOW}=== Checking WiFi Configuration ===${NC}"
echo ""

echo -n "wpa_supplicant.conf exists... "
if run_remote "[ -f /etc/wpa_supplicant/wpa_supplicant.conf ]" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ OK${NC}"
else
    echo -e "${RED}✗ NOT FOUND${NC}"
fi

echo -n "wpa_cli accessible... "
if run_remote "wpa_cli -i wlan0 status" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ OK${NC}"
else
    echo -e "${RED}✗ FAILED${NC}"
fi

echo ""

# Test 5: Try to run the script (dry run)
echo -e "${YELLOW}=== Testing Script Execution ===${NC}"
echo ""

echo "Attempting to run force-ap-mode.sh with sudo..."
echo "(This will show any permission errors)"
echo ""

# Try to run the script but interrupt it before reboot
result=$(run_remote "timeout 2 sudo -n bash /home/pi/ovbuddy/force-ap-mode.sh 2>&1 || true")
echo "$result"

echo ""

# Summary
echo -e "${BLUE}=========================================="
echo "Summary"
echo -e "==========================================${NC}"
echo ""

if run_remote "sudo -n bash /home/pi/ovbuddy/force-ap-mode.sh --help" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Force AP mode should work!${NC}"
    echo ""
    echo "To test, run:"
    echo "  ./scripts/force-ap-mode.sh"
    echo ""
    echo "Or via web interface:"
    echo "  http://ovbuddy.local:8080"
    echo "  Click 'Force AP Mode' button"
else
    echo -e "${RED}✗ Force AP mode will NOT work${NC}"
    echo ""
    echo "To fix:"
    echo "  1. Run: ./scripts/setup-passwordless-sudo.sh"
    echo "  2. Run: ./scripts/deploy.sh"
    echo "  3. Run this test again"
fi

echo ""




