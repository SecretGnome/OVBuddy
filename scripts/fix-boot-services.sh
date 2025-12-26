#!/bin/bash

# Script to diagnose and fix services that don't start on boot
# This script checks and fixes avahi-daemon and ovbuddy-wifi services

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

echo -e "${BLUE}=========================================="
echo "OVBuddy Boot Services Diagnostic & Fix"
echo -e "==========================================${NC}"
echo ""
echo "Connecting to: ${PI_USER}@${PI_SSH_HOST}"
echo ""

# Function to run remote command
run_remote() {
    sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "$1" 2>/dev/null
}

# Function to check service status
check_service() {
    local service=$1
    local status=$(run_remote "systemctl is-active $service 2>/dev/null || echo 'inactive'")
    local enabled=$(run_remote "systemctl is-enabled $service 2>/dev/null || echo 'disabled'")
    
    echo -e "${YELLOW}Service: $service${NC}"
    echo "  Status: $status"
    echo "  Enabled: $enabled"
    
    if [ "$status" != "active" ]; then
        echo -e "  ${RED}✗ Service is not running${NC}"
        return 1
    else
        echo -e "  ${GREEN}✓ Service is running${NC}"
        return 0
    fi
}

# Check current status
echo -e "${BLUE}=== Current Service Status ===${NC}"
echo ""

AVAHI_OK=false
WIFI_OK=false
OVBUDDY_OK=false
WEB_OK=false

check_service "avahi-daemon" && AVAHI_OK=true || true
echo ""
check_service "ovbuddy-wifi" && WIFI_OK=true || true
echo ""
check_service "ovbuddy" && OVBUDDY_OK=true || true
echo ""
check_service "ovbuddy-web" && WEB_OK=true || true
echo ""

# Check for errors in logs
echo -e "${BLUE}=== Recent Service Logs ===${NC}"
echo ""

if [ "$AVAHI_OK" = false ]; then
    echo -e "${YELLOW}avahi-daemon logs (last 10 lines):${NC}"
    run_remote "journalctl -u avahi-daemon -n 10 --no-pager" || echo "  (no logs)"
    echo ""
fi

if [ "$WIFI_OK" = false ]; then
    echo -e "${YELLOW}ovbuddy-wifi logs (last 10 lines):${NC}"
    run_remote "journalctl -u ovbuddy-wifi -n 10 --no-pager" || echo "  (no logs)"
    echo ""
fi

# Apply fixes
echo -e "${BLUE}=== Applying Fixes ===${NC}"
echo ""

if [ "$AVAHI_OK" = false ]; then
    echo -e "${YELLOW}Fixing avahi-daemon...${NC}"
    
    # Unmask and enable
    run_remote "sudo -n systemctl unmask avahi-daemon 2>/dev/null || true"
    run_remote "sudo -n systemctl enable avahi-daemon 2>/dev/null || true"
    echo "  ✓ Unmasked and enabled avahi-daemon"
    
    # Start it
    run_remote "sudo -n systemctl start avahi-daemon 2>/dev/null || true"
    sleep 2
    
    # Check if it's running now
    status=$(run_remote "systemctl is-active avahi-daemon 2>/dev/null || echo 'inactive'")
    if [ "$status" = "active" ]; then
        echo -e "  ${GREEN}✓ avahi-daemon is now running${NC}"
        AVAHI_OK=true
    else
        echo -e "  ${RED}✗ avahi-daemon failed to start${NC}"
        echo "  Check logs: ssh ${PI_USER}@${PI_SSH_HOST} 'sudo journalctl -u avahi-daemon -n 50'"
    fi
    echo ""
fi

if [ "$WIFI_OK" = false ]; then
    echo -e "${YELLOW}Fixing ovbuddy-wifi...${NC}"
    
    # Check if service file exists
    service_exists=$(run_remote "[ -f /etc/systemd/system/ovbuddy-wifi.service ] && echo 'yes' || echo 'no'")
    
    if [ "$service_exists" = "no" ]; then
        echo -e "  ${RED}✗ Service file not found, needs deployment${NC}"
        echo "  Run: ./scripts/deploy.sh"
    else
        # Enable the service
        run_remote "sudo -n systemctl enable ovbuddy-wifi 2>/dev/null || true"
        echo "  ✓ Enabled ovbuddy-wifi"
        
        # Start it
        run_remote "sudo -n systemctl start ovbuddy-wifi 2>/dev/null || true"
        sleep 2
        
        # Check if it's running now
        status=$(run_remote "systemctl is-active ovbuddy-wifi 2>/dev/null || echo 'inactive'")
        if [ "$status" = "active" ]; then
            echo -e "  ${GREEN}✓ ovbuddy-wifi is now running${NC}"
            WIFI_OK=true
        else
            echo -e "  ${RED}✗ ovbuddy-wifi failed to start${NC}"
            echo "  Check logs: ssh ${PI_USER}@${PI_SSH_HOST} 'sudo journalctl -u ovbuddy-wifi -n 50'"
        fi
    fi
    echo ""
fi

# Verify fix-bonjour service
echo -e "${YELLOW}Checking fix-bonjour service...${NC}"
fix_bonjour_enabled=$(run_remote "systemctl is-enabled fix-bonjour 2>/dev/null || echo 'disabled'")
echo "  fix-bonjour enabled: $fix_bonjour_enabled"

if [ "$fix_bonjour_enabled" != "enabled" ]; then
    echo "  Enabling fix-bonjour service..."
    run_remote "sudo -n systemctl enable fix-bonjour 2>/dev/null || true"
    echo -e "  ${GREEN}✓ fix-bonjour enabled${NC}"
fi
echo ""

# Summary
echo -e "${BLUE}=== Summary ===${NC}"
echo ""

if [ "$AVAHI_OK" = true ] && [ "$WIFI_OK" = true ] && [ "$OVBUDDY_OK" = true ] && [ "$WEB_OK" = true ]; then
    echo -e "${GREEN}✓ All services are running!${NC}"
    echo ""
    echo "Services will now start automatically on boot."
else
    echo -e "${YELLOW}Some services are not running:${NC}"
    [ "$AVAHI_OK" = false ] && echo "  - avahi-daemon"
    [ "$WIFI_OK" = false ] && echo "  - ovbuddy-wifi"
    [ "$OVBUDDY_OK" = false ] && echo "  - ovbuddy"
    [ "$WEB_OK" = false ] && echo "  - ovbuddy-web"
    echo ""
    echo "To troubleshoot:"
    echo "  ssh ${PI_USER}@${PI_SSH_HOST}"
    [ "$AVAHI_OK" = false ] && echo "  sudo journalctl -u avahi-daemon -f"
    [ "$WIFI_OK" = false ] && echo "  sudo journalctl -u ovbuddy-wifi -f"
fi

echo ""
echo -e "${BLUE}=== Testing Boot Persistence ===${NC}"
echo ""
echo "To test if services start on boot:"
echo "  1. Reboot the device: ssh ${PI_USER}@${PI_SSH_HOST} 'sudo reboot'"
echo "  2. Wait 60 seconds"
echo "  3. Run this script again to verify"
echo ""




