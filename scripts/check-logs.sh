#!/bin/bash

# Script to remotely check service logs on Raspberry Pi
# Reads credentials from .env file
# Usage: ./scripts/check-logs.sh [service-name] [num-lines]
#   service-name: ovbuddy or ovbuddy-web (default: ovbuddy)
#   num-lines: number of log lines to show (default: 50)

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

# Parse arguments
SERVICE_NAME="${1:-ovbuddy}"
NUM_LINES="${2:-50}"

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

echo -e "${YELLOW}Checking ${SERVICE_NAME} service on ${PI_USER}@${PI_SSH_HOST}${NC}"
echo ""

# Check service status
echo "=== Service Status ==="
sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "systemctl status ${SERVICE_NAME} --no-pager -l" 2>/dev/null || true

echo ""
echo "=== Recent Logs (last ${NUM_LINES} lines) ==="
sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "sudo journalctl -u ${SERVICE_NAME} -n ${NUM_LINES} --no-pager" 2>/dev/null || {
    echo -e "${RED}Error: Could not fetch logs${NC}"
    exit 1
}

echo ""
echo -e "${GREEN}Done!${NC}"
echo ""
echo "To follow logs in real-time:"
echo "  ssh ${PI_USER}@${PI_SSH_HOST}"
echo "  sudo journalctl -u ${SERVICE_NAME} -f"

