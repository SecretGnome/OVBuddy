#!/bin/bash

# Persistent Bonjour/mDNS fix script
# This script removes .local entries from /etc/hosts that interfere with mDNS
# Should be run on boot via systemd service

# Remove .local entries and hostname mappings to localhost from /etc/hosts
if [ -f /etc/hosts ]; then
    HOSTNAME=$(hostname)
    
    # Remove lines containing .local (but keep localhost entries)
    sed -i '/\.local/d' /etc/hosts
    
    # Remove entries that map hostname to 127.0.1.1 or 127.0.0.1 (but keep localhost)
    # This is common on Debian/Ubuntu and interferes with mDNS
    if [ -n "$HOSTNAME" ]; then
        # Remove entries like "127.0.1.1 ovbuddy" or "127.0.0.1 ovbuddy"
        sed -i "/^127\.0\.1\.1[[:space:]]\+${HOSTNAME}/d" /etc/hosts
        sed -i "/^127\.0\.0\.1[[:space:]]\+${HOSTNAME}/d" /etc/hosts
        # Also remove entries with hostname.local
        sed -i "/${HOSTNAME}\.local/d" /etc/hosts
        # Remove any line that has hostname followed by .local anywhere
        sed -i "/[[:space:]]${HOSTNAME}\.local/d" /etc/hosts
    fi
fi

# Ensure hostname is set to ovbuddy (if not already)
CURRENT_HOSTNAME=$(hostname)
if [ "$CURRENT_HOSTNAME" != "ovbuddy" ]; then
    hostnamectl set-hostname ovbuddy 2>/dev/null || true
fi

# Ensure avahi-daemon is enabled and started
systemctl enable avahi-daemon 2>/dev/null || true

# Start or restart avahi-daemon to pick up changes
if systemctl is-active avahi-daemon >/dev/null 2>&1; then
    # Already running, restart it
    sleep 1
    systemctl reload-or-restart avahi-daemon 2>/dev/null || systemctl try-restart avahi-daemon 2>/dev/null || true
    echo "✓ Fixed /etc/hosts, hostname, and restarted avahi-daemon"
else
    # Not running, start it
    systemctl start avahi-daemon 2>/dev/null || true
    sleep 1
    if systemctl is-active avahi-daemon >/dev/null 2>&1; then
        echo "✓ Fixed /etc/hosts, hostname, and started avahi-daemon"
    else
        echo "⚠ Fixed /etc/hosts and hostname, but avahi-daemon failed to start"
    fi
fi

exit 0

