#!/bin/bash

# Script to remotely display an image on the e-ink display
# Reads credentials from .env file
# Usage: ./scripts/display-image.sh <image.jpg>

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

# Check if image file is provided
if [ $# -lt 1 ]; then
    echo -e "${RED}Error: Image file required${NC}"
    echo "Usage: $0 <image.jpg>"
    echo ""
    echo "Optional environment variables:"
    echo "  INVERTED=1       - Invert colors (white on black)"
    echo "  FLIP_DISPLAY=1  - Rotate display 180 degrees"
    exit 1
fi

IMAGE_FILE="$1"

# Check if image file exists
if [ ! -f "$IMAGE_FILE" ]; then
    echo -e "${RED}Error: Image file not found: $IMAGE_FILE${NC}"
    exit 1
fi

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
SCP_OPTS="-o StrictHostKeyChecking=no"
REMOTE_DIR="/home/${PI_USER}/ovbuddy"
IMAGE_FILENAME=$(basename "$IMAGE_FILE")
REMOTE_IMAGE_PATH="${REMOTE_DIR}/${IMAGE_FILENAME}"

echo -e "${YELLOW}Displaying image on ${PI_USER}@${PI_HOST}${NC}"
echo "Image: $IMAGE_FILE"
echo ""

# Upload image file to Raspberry Pi
echo "Uploading image..."
sshpass -p "$PI_PASSWORD" scp $SCP_OPTS "$IMAGE_FILE" "${PI_USER}@${PI_HOST}:${REMOTE_IMAGE_PATH}"

# Run display_image.py on the Raspberry Pi
# Pass through INVERTED and FLIP_DISPLAY environment variables if set
ENV_VARS=""
if [ -n "$INVERTED" ]; then
    ENV_VARS="INVERTED=$INVERTED "
fi
if [ -n "$FLIP_DISPLAY" ]; then
    ENV_VARS="${ENV_VARS}FLIP_DISPLAY=$FLIP_DISPLAY "
fi

echo "Displaying image on e-ink display..."
sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_HOST}" "cd ${REMOTE_DIR} && ${ENV_VARS}python3 display_image.py ${REMOTE_IMAGE_PATH}"

# Optionally clean up the uploaded image file
read -p "Remove uploaded image from Raspberry Pi? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Removing uploaded image..."
    sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_HOST}" "rm -f ${REMOTE_IMAGE_PATH}"
    echo -e "${GREEN}Image removed${NC}"
fi

echo -e "${GREEN}Image displayed successfully!${NC}"

