#!/bin/bash

# Script to remotely check OVBuddy version and update status
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
BLUE='\033[0;34m'
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

SSH_OPTS="-o StrictHostKeyChecking=no"

echo -e "${BLUE}Checking OVBuddy version and update status on ${PI_USER}@${PI_HOST}${NC}"
echo ""

# Try to get version via web API first (most reliable)
echo -e "${YELLOW}Checking via web API...${NC}"
VERSION_RESPONSE=$(curl -s "http://${PI_HOST}:8080/api/version" 2>/dev/null || echo "")

if [ -n "$VERSION_RESPONSE" ] && echo "$VERSION_RESPONSE" | grep -q "running_version"; then
    # Parse JSON response (simple parsing, assumes jq is not available)
    RUNNING_VERSION=$(echo "$VERSION_RESPONSE" | grep -o '"running_version":"[^"]*"' | cut -d'"' -f4)
    FILE_VERSION=$(echo "$VERSION_RESPONSE" | grep -o '"file_version":"[^"]*"' | cut -d'"' -f4)
    LATEST_VERSION=$(echo "$VERSION_RESPONSE" | grep -o '"latest_version":"[^"]*"' | cut -d'"' -f4)
    UPDATE_IN_PROGRESS=$(echo "$VERSION_RESPONSE" | grep -o '"update_in_progress":[^,}]*' | grep -o '[tf][ar][ul][se]' || echo "false")
    VERSION_MISMATCH=$(echo "$VERSION_RESPONSE" | grep -o '"version_mismatch":[^,}]*' | grep -o '[tf][ar][ul][se]' || echo "false")
    NEEDS_RESTART=$(echo "$VERSION_RESPONSE" | grep -o '"needs_restart":[^,}]*' | grep -o '[tf][ar][ul][se]' || echo "false")
    
    echo -e "${GREEN}✓ Web API accessible${NC}"
    echo ""
    echo -e "${BLUE}Version Information:${NC}"
    echo -e "  Running version: ${GREEN}${RUNNING_VERSION:-unknown}${NC}"
    echo -e "  File version:    ${GREEN}${FILE_VERSION:-unknown}${NC}"
    echo -e "  Latest version:  ${GREEN}${LATEST_VERSION:-unknown}${NC}"
    echo ""
    
    if [ "$VERSION_MISMATCH" = "true" ]; then
        echo -e "${YELLOW}⚠ Version mismatch detected!${NC}"
        echo -e "  The file on disk (${FILE_VERSION}) differs from running version (${RUNNING_VERSION})"
        echo -e "  The service needs to be restarted to apply the update."
    fi
    
    if [ "$UPDATE_IN_PROGRESS" = "true" ]; then
        echo -e "${YELLOW}⚠ Update in progress...${NC}"
        echo -e "  An update is currently being performed."
    fi
    
    if [ "$NEEDS_RESTART" = "true" ]; then
        echo -e "${YELLOW}⚠ Service restart required${NC}"
    fi
    
    # Show full JSON if verbose
    if [ "$1" = "-v" ] || [ "$1" = "--verbose" ]; then
        echo ""
        echo -e "${BLUE}Full API Response:${NC}"
        echo "$VERSION_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$VERSION_RESPONSE"
    fi
else
    echo -e "${YELLOW}⚠ Web API not accessible, trying SSH method...${NC}"
    
    # Fallback: Check via SSH
    if ! command -v sshpass &> /dev/null; then
        echo -e "${RED}Error: sshpass is required for SSH authentication${NC}"
        echo "Install it with:"
        echo "  macOS: brew install hudochenkov/sshpass/sshpass"
        echo "  Linux: apt-get install sshpass"
        exit 1
    fi
    
    # Check version from file
    echo ""
    echo -e "${YELLOW}Checking version via SSH...${NC}"
    
    # Try to find the installation directory
    REMOTE_DIR=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_HOST}" \
        "systemctl show ovbuddy -p ExecStart --value 2>/dev/null | sed 's|python3 ||' | xargs dirname 2>/dev/null || echo '/home/pi/ovbuddy'" 2>/dev/null)
    
    # Get running version from service
    RUNNING_VERSION=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_HOST}" \
        "sudo journalctl -u ovbuddy -n 50 --no-pager 2>/dev/null | grep -o 'OVBuddy v[0-9.]*' | tail -1 | grep -o '[0-9.]*' || echo 'unknown'" 2>/dev/null)
    
    # Get file version
    FILE_VERSION=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_HOST}" \
        "grep -o 'VERSION = \"[0-9.]*\"' ${REMOTE_DIR}/ovbuddy.py 2>/dev/null | grep -o '[0-9.]*' || echo 'unknown'" 2>/dev/null)
    
    # Check update status file
    UPDATE_STATUS=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_HOST}" \
        "cat ${REMOTE_DIR}/.update_status.json 2>/dev/null || echo '{}'" 2>/dev/null)
    
    echo ""
    echo -e "${BLUE}Version Information:${NC}"
    echo -e "  Running version: ${GREEN}${RUNNING_VERSION}${NC}"
    echo -e "  File version:    ${GREEN}${FILE_VERSION}${NC}"
    
    if [ "$RUNNING_VERSION" != "$FILE_VERSION" ] && [ "$RUNNING_VERSION" != "unknown" ] && [ "$FILE_VERSION" != "unknown" ]; then
        echo ""
        echo -e "${YELLOW}⚠ Version mismatch detected!${NC}"
        echo -e "  The file on disk (${FILE_VERSION}) differs from running version (${RUNNING_VERSION})"
        echo -e "  The service needs to be restarted to apply the update."
    fi
    
    # Parse update status if available
    if echo "$UPDATE_STATUS" | grep -q "update_in_progress"; then
        IN_PROGRESS=$(echo "$UPDATE_STATUS" | grep -o '"update_in_progress":[^,}]*' | grep -o '[tf][ar][ul][se]' || echo "false")
        if [ "$IN_PROGRESS" = "true" ]; then
            echo ""
            echo -e "${YELLOW}⚠ Update in progress...${NC}"
        fi
    fi
fi

echo ""
echo -e "${GREEN}Version check complete!${NC}"
















