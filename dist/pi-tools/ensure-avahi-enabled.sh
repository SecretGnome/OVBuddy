#!/bin/bash

# Script to ensure avahi-daemon is properly enabled and will start on boot
# Run this on the Raspberry Pi to fix avahi-daemon boot issues

set -e

echo "=== Ensuring avahi-daemon is enabled and will start on boot ==="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root (use sudo)"
    exit 1
fi

# Install avahi-daemon if not present
if ! command -v avahi-daemon >/dev/null 2>&1; then
    echo "avahi-daemon not found, installing..."
    apt-get update -qq
    apt-get install -y avahi-daemon avahi-utils
    echo "✓ Installed avahi-daemon"
else
    echo "✓ avahi-daemon is installed"
fi

# Unmask avahi-daemon (in case it was masked)
echo ""
echo "Unmasking avahi-daemon..."
systemctl unmask avahi-daemon 2>/dev/null || true
echo "✓ avahi-daemon unmasked"

# Enable avahi-daemon to start on boot
echo ""
echo "Enabling avahi-daemon to start on boot..."
systemctl enable avahi-daemon
echo "✓ avahi-daemon enabled"

# Check if it's currently running
echo ""
if systemctl is-active avahi-daemon >/dev/null 2>&1; then
    echo "avahi-daemon is currently running"
    echo "Restarting to ensure clean state..."
    systemctl restart avahi-daemon
    echo "✓ avahi-daemon restarted"
else
    echo "avahi-daemon is not running, starting it..."
    systemctl start avahi-daemon
    sleep 2
    if systemctl is-active avahi-daemon >/dev/null 2>&1; then
        echo "✓ avahi-daemon started successfully"
    else
        echo "✗ Failed to start avahi-daemon"
        echo ""
        echo "Status:"
        systemctl status avahi-daemon --no-pager -l || true
        exit 1
    fi
fi

# Verify status
echo ""
echo "=== Final Status ==="
echo ""
echo "Enabled status:"
systemctl is-enabled avahi-daemon && echo "  ✓ avahi-daemon is enabled" || echo "  ✗ avahi-daemon is NOT enabled"
echo ""
echo "Active status:"
systemctl is-active avahi-daemon && echo "  ✓ avahi-daemon is running" || echo "  ✗ avahi-daemon is NOT running"
echo ""
echo "Full status:"
systemctl status avahi-daemon --no-pager -l || true

echo ""
echo "=== Configuration Check ==="
echo ""
echo "Hostname: $(hostname)"
echo "Expected: ovbuddy"
echo ""
echo "Checking /etc/hosts for .local entries that might interfere:"
if grep -q "\.local" /etc/hosts 2>/dev/null; then
    echo "  ⚠ Found .local entries in /etc/hosts (these may interfere with mDNS):"
    grep "\.local" /etc/hosts
    echo ""
    echo "  Run the fix-bonjour service to clean these up:"
    echo "    sudo systemctl start fix-bonjour.service"
else
    echo "  ✓ No .local entries found in /etc/hosts"
fi

echo ""
echo "=== Complete ==="
echo ""
echo "avahi-daemon should now start automatically on boot."
echo "To test, you can reboot the Pi and check if mDNS works:"
echo "  sudo reboot"
echo ""
echo "After reboot, from your Mac:"
echo "  ping ovbuddy.local"
echo "  ssh pi@ovbuddy.local"











