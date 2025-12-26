#!/bin/bash

# Script to install ovbuddy as a systemd service on Raspberry Pi
# This is now a wrapper for install-all-services.sh which handles all services

set -e

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root (use sudo)"
    exit 1
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if unified installer exists
if [ -f "$SCRIPT_DIR/install-all-services.sh" ]; then
    echo "Using unified service installer..."
    exec bash "$SCRIPT_DIR/install-all-services.sh"
else
    echo "Error: install-all-services.sh not found!"
    echo "Please ensure all installation files are present."
    exit 1
fi


