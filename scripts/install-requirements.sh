#!/bin/bash
# Install Python requirements on the Raspberry Pi

set -e

# Configuration
PI_HOST="${PI_HOST:-pi@ovbuddy.local}"
REMOTE_DIR="/home/pi/ovbuddy"

echo "Installing requirements on ${PI_HOST}"
echo "Remote directory: ${REMOTE_DIR}"
echo ""

# First, install system dependencies
echo "Installing system dependencies..."
# `git` is required for the on-device auto-updater (it uses `git clone`).
ssh "${PI_HOST}" "sudo apt-get update && sudo apt-get install -y git python3-pip python3-pil python3-numpy libopenjp2-7"

# Upload requirements.txt if needed
echo ""
echo "Uploading requirements.txt..."
scp dist/requirements.txt "${PI_HOST}:${REMOTE_DIR}/"

# Install Python packages
echo ""
echo "Installing Python packages..."
ssh "${PI_HOST}" "cd ${REMOTE_DIR} && pip3 install -r requirements.txt --break-system-packages"

echo ""
echo "✓ Requirements installed successfully!"
echo ""
echo "Note: The --break-system-packages flag is used because Raspberry Pi OS"
echo "uses externally-managed Python. This is safe for this use case."


