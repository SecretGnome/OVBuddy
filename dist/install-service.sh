#!/bin/bash

# Script to install ovbuddy as a systemd service on Raspberry Pi

set -e

SERVICE_FILE="ovbuddy.service"
SERVICE_NAME="ovbuddy"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}.service"

WEB_SERVICE_FILE="ovbuddy-web.service"
WEB_SERVICE_NAME="ovbuddy-web"
WEB_SERVICE_PATH="/etc/systemd/system/${WEB_SERVICE_NAME}.service"

echo "Installing ovbuddy systemd service..."

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root (use sudo)"
    exit 1
fi

# Check if main service file exists
if [ ! -f "$SERVICE_FILE" ]; then
    echo "Error: $SERVICE_FILE not found!"
    exit 1
fi

# Copy main service file to systemd directory
cp "$SERVICE_FILE" "$SERVICE_PATH"
echo "✓ Copied service file to $SERVICE_PATH"

# Optionally install web service (if present in dist/)
WEB_SERVICE_INSTALLED=false
if [ -f "$WEB_SERVICE_FILE" ]; then
    cp "$WEB_SERVICE_FILE" "$WEB_SERVICE_PATH"
    echo "✓ Copied web service file to $WEB_SERVICE_PATH"
    WEB_SERVICE_INSTALLED=true
fi

# Stop services first if they're running (to release ports, etc.)
echo "Stopping services if running..."
systemctl stop "$SERVICE_NAME" 2>/dev/null || true
if [ "$WEB_SERVICE_INSTALLED" = true ]; then
    systemctl stop "$WEB_SERVICE_NAME" 2>/dev/null || true
fi

# Also kill any stray ovbuddy.py processes that might be holding GPIO
echo "Checking for stray ovbuddy processes..."
pkill -f "ovbuddy.py" 2>/dev/null || true

# Wait a few seconds for services to fully stop, processes to exit, and GPIO to be released
echo "Waiting for services and GPIO to be released..."
sleep 5

# Reload systemd
systemctl daemon-reload
echo "✓ Reloaded systemd daemon"

# Enable services to start on boot
systemctl enable "$SERVICE_NAME"
echo "✓ Enabled $SERVICE_NAME to start on boot"

if [ "$WEB_SERVICE_INSTALLED" = true ]; then
    systemctl enable "$WEB_SERVICE_NAME"
    echo "✓ Enabled $WEB_SERVICE_NAME to start on boot"
fi

# Start the services
systemctl start "$SERVICE_NAME"
echo "✓ Started $SERVICE_NAME"

if [ "$WEB_SERVICE_INSTALLED" = true ]; then
    systemctl start "$WEB_SERVICE_NAME"
    echo "✓ Started $WEB_SERVICE_NAME"
fi

# Show status
echo ""
echo "Service status:"
systemctl status "$SERVICE_NAME" --no-pager -l

if [ "$WEB_SERVICE_INSTALLED" = true ]; then
    echo ""
    echo "Web service status:"
    systemctl status "$WEB_SERVICE_NAME" --no-pager -l
fi

echo ""
echo "Installation complete!"
echo ""
echo "Useful commands:"
echo "  sudo systemctl status $SERVICE_NAME          # Check display service status"
echo "  sudo systemctl stop $SERVICE_NAME             # Stop display service"
echo "  sudo systemctl start $SERVICE_NAME            # Start display service"
echo "  sudo systemctl restart $SERVICE_NAME          # Restart display service"
echo "  sudo journalctl -u $SERVICE_NAME -f          # View display logs (follow)"
echo "  sudo systemctl disable $SERVICE_NAME         # Disable display auto-start"
if [ "$WEB_SERVICE_INSTALLED" = true ]; then
    echo "  sudo systemctl status $WEB_SERVICE_NAME      # Check web service status"
    echo "  sudo systemctl stop $WEB_SERVICE_NAME         # Stop web service"
    echo "  sudo systemctl start $WEB_SERVICE_NAME        # Start web service"
    echo "  sudo systemctl restart $WEB_SERVICE_NAME      # Restart web service"
    echo "  sudo journalctl -u $WEB_SERVICE_NAME -f      # View web logs (follow)"
    echo "  sudo systemctl disable $WEB_SERVICE_NAME     # Disable web auto-start"
fi


