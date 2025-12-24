#!/bin/bash

# Script to remotely trigger a fetch & refresh on the Raspberry Pi
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
REMOTE_DIR="/home/${PI_USER}/ovbuddy"

echo -e "${YELLOW}Triggering refresh on ${PI_USER}@${PI_HOST}${NC}"

# Method 1: Try to send USR1 signal to trigger refresh (if script handles signals)
# First, find the process
PID=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_HOST}" "pgrep -f 'python3.*ovbuddy.py' | head -1" 2>/dev/null || echo "")

if [ -n "$PID" ]; then
    echo "Found ovbuddy process (PID: $PID), sending refresh signal..."
    # Try to send USR1 signal (if the script handles it)
    sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_HOST}" "sudo kill -USR1 $PID" 2>/dev/null && echo -e "${GREEN}Refresh signal sent!${NC}" || {
        echo "Signal method not available, using file trigger..."
        # Method 2: Create a trigger file
        sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_HOST}" "touch ${REMOTE_DIR}/.refresh_trigger"
        echo -e "${GREEN}Refresh trigger file created!${NC}"
    }
else
    echo "Process not found, creating trigger file..."
    # Method 2: Create a trigger file
    sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_HOST}" "touch ${REMOTE_DIR}/.refresh_trigger"
    echo -e "${GREEN}Refresh trigger file created!${NC}"
fi

echo ""
echo "Note: The service will check for the trigger on the next refresh cycle."
echo "To force immediate refresh, you can restart the service:"
echo "  ./scripts/restart-service.sh"

