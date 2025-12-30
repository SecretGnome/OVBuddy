#!/bin/bash

# Script to install fix-bonjour systemd service and timer on Raspberry Pi
# This ensures Bonjour/mDNS works correctly after reboots

set -e

SERVICE_FILE="fix-bonjour.service"
TIMER_FILE="fix-bonjour.timer"
SCRIPT_FILE="fix-bonjour-persistent.sh"
SERVICE_NAME="fix-bonjour"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}.service"
TIMER_PATH="/etc/systemd/system/${SERVICE_NAME}.timer"
SCRIPT_PATH="/usr/local/bin/${SCRIPT_FILE}"

echo "Installing fix-bonjour systemd service and timer..."

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root (use sudo)"
    exit 1
fi

# Check if service file exists
if [ ! -f "$SERVICE_FILE" ]; then
    echo "Error: $SERVICE_FILE not found!"
    exit 1
fi

# First, ensure avahi-daemon is installed and enabled
echo ""
echo "Ensuring avahi-daemon is installed and enabled..."
if ! command -v avahi-daemon >/dev/null 2>&1; then
    echo "Installing avahi-daemon..."
    apt-get update -qq
    apt-get install -y avahi-daemon avahi-utils
    echo "✓ Installed avahi-daemon"
else
    echo "✓ avahi-daemon is already installed"
fi

# Unmask and enable avahi-daemon
systemctl unmask avahi-daemon 2>/dev/null || true
echo "✓ Unmasked avahi-daemon"
systemctl enable avahi-daemon 2>/dev/null || true
echo "✓ Enabled avahi-daemon to start on boot"

# Copy script to /usr/local/bin/
if [ -f "$SCRIPT_FILE" ]; then
    cp "$SCRIPT_FILE" "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"
    echo "✓ Copied script to $SCRIPT_PATH"
else
    echo "Warning: $SCRIPT_FILE not found, service may not work correctly"
fi

# Copy service file to systemd directory (will be modified to use script path)
cp "$SERVICE_FILE" "$SERVICE_PATH"
echo "✓ Copied service file to $SERVICE_PATH"

# Copy timer file if it exists
if [ -f "$TIMER_FILE" ]; then
    cp "$TIMER_FILE" "$TIMER_PATH"
    echo "✓ Copied timer file to $TIMER_PATH"
fi

# Reload systemd
systemctl daemon-reload
echo "✓ Reloaded systemd daemon"

# Enable the service (will start on boot)
systemctl enable "$SERVICE_NAME"
echo "✓ Enabled service to start on boot"

# Skip immediate start to avoid hangs - service will run on boot
# If you want to test it immediately, run: sudo systemctl start fix-bonjour.service
echo "✓ Service will run automatically on boot"

# Enable and start the timer if it exists
if [ -f "$TIMER_FILE" ]; then
    systemctl enable "$SERVICE_NAME.timer"
    echo "✓ Enabled timer to run periodically"
    systemctl start "$SERVICE_NAME.timer"
    echo "✓ Started timer"
fi

# Show status
echo ""
echo "Service status:"
systemctl status "$SERVICE_NAME" --no-pager -l || true

if [ -f "$TIMER_FILE" ]; then
    echo ""
    echo "Timer status:"
    systemctl status "$SERVICE_NAME.timer" --no-pager -l || true
fi

echo ""
echo "Installation complete!"
echo ""
echo "Useful commands:"
echo "  sudo systemctl status $SERVICE_NAME        # Check service status"
echo "  sudo systemctl status $SERVICE_NAME.timer   # Check timer status"
echo "  sudo journalctl -u $SERVICE_NAME -f       # View service logs (follow)"
if [ -f "$TIMER_FILE" ]; then
    echo "  sudo systemctl list-timers $SERVICE_NAME # List timer schedule"
fi





