#!/bin/bash
# Script to check Pi logs - run this to see what's happening

PI_HOST="${PI_HOST:-192.168.1.170}"

echo "Checking OVBuddy service status and logs..."
echo "============================================"
echo ""

# Check if we can reach the Pi
if ! ping -c 1 -W 1 "$PI_HOST" > /dev/null 2>&1; then
    echo "❌ Cannot reach Pi at $PI_HOST"
    exit 1
fi

echo "Service status:"
ssh pi@"$PI_HOST" "sudo systemctl status ovbuddy --no-pager -l" 2>&1 | head -20

echo ""
echo "Recent logs (last 50 lines):"
echo "----------------------------"
ssh pi@"$PI_HOST" "sudo journalctl -u ovbuddy -n 50 --no-pager" 2>&1 | tail -50

