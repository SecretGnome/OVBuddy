#!/bin/bash

# Script to check and troubleshoot the ovbuddy service

SERVICE_NAME="ovbuddy"

echo "=== Checking ovbuddy service status ==="
echo ""

# Check if service exists
if systemctl list-unit-files | grep -q "$SERVICE_NAME.service"; then
    echo "✓ Service file exists"
else
    echo "✗ Service file NOT found!"
    echo "  Run: sudo ./install-service.sh"
    exit 1
fi

echo ""
echo "=== Service Status ==="
systemctl status "$SERVICE_NAME" --no-pager -l || true

echo ""
echo "=== Recent Logs (last 50 lines) ==="
journalctl -u "$SERVICE_NAME" -n 50 --no-pager || true

echo ""
echo "=== Checking if service is enabled ==="
if systemctl is-enabled "$SERVICE_NAME" > /dev/null 2>&1; then
    echo "✓ Service is enabled (will start on boot)"
else
    echo "✗ Service is NOT enabled"
    echo "  Run: sudo systemctl enable $SERVICE_NAME"
fi

echo ""
echo "=== Checking if service is active ==="
if systemctl is-active "$SERVICE_NAME" > /dev/null 2>&1; then
    echo "✓ Service is running"
else
    echo "✗ Service is NOT running"
    echo "  Try: sudo systemctl start $SERVICE_NAME"
    echo "  Then check logs: sudo journalctl -u $SERVICE_NAME -f"
fi

echo ""
echo "=== Checking Python path ==="
PYTHON_PATH=$(which python3)
echo "Python3 path: $PYTHON_PATH"

echo ""
echo "=== Checking if script exists ==="
SCRIPT_PATH="/home/pi/ovbuddy/ovbuddy.py"
if [ -f "$SCRIPT_PATH" ]; then
    echo "✓ Script exists at $SCRIPT_PATH"
else
    echo "✗ Script NOT found at $SCRIPT_PATH"
fi

echo ""
echo "=== Testing script manually ==="
echo "You can test the script manually with:"
echo "  cd /home/pi/ovbuddy"
echo "  python3 ovbuddy.py"





