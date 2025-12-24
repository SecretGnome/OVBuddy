#!/bin/bash

# Script to remotely restart the ovbuddy service on Raspberry Pi
# Reads credentials from .env file

# Change to project root directory (parent of scripts/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if .env file exists
if [ ! -f .env ]; then
    echo -e "${RED}Error: .env file not found!${NC}"
    echo "Please create a .env file with the following variables:"
    echo "  PI_HOST=raspberrypi.local"
    echo "  PI_USER=pi"
    echo "  PI_PASSWORD=your_password"
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

# Check if sshpass is installed (needed for password auth)
if ! command -v sshpass &> /dev/null; then
    echo -e "${RED}Error: sshpass is required for password authentication${NC}"
    echo "Install it with:"
    echo "  macOS: brew install hudochenkov/sshpass/sshpass"
    echo "  Linux: apt-get install sshpass"
    exit 1
fi

SSH_OPTS="-o StrictHostKeyChecking=no"
SERVICE_NAME="ovbuddy"

echo -e "${YELLOW}Restarting ovbuddy service on ${PI_USER}@${PI_HOST}${NC}"

# Restart the service
echo "Restarting service..."
sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_HOST}" "sudo systemctl restart ${SERVICE_NAME}"

# Wait a moment for service to start
sleep 2

# Check status
echo "Checking service status..."
sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_HOST}" "sudo systemctl status ${SERVICE_NAME} --no-pager -l | head -15"

echo -e "${GREEN}Service restart complete!${NC}"
echo ""
echo "To view live logs:"
echo "  ssh ${PI_USER}@${PI_HOST}"
echo "  sudo journalctl -u ${SERVICE_NAME} -f"

