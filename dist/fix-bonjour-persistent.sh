#!/bin/bash

# Persistent Bonjour/mDNS fix script
# This script removes .local entries from /etc/hosts that interfere with mDNS
# Should be run on boot via systemd service

# Log to journald
log() {
    echo "$1"
    logger -t fix-bonjour "$1"
}

log "Starting Bonjour/mDNS fix..."

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
    log "✓ Cleaned /etc/hosts"
fi

# Ensure hostname is set to ovbuddy (if not already)
CURRENT_HOSTNAME=$(hostname)
if [ "$CURRENT_HOSTNAME" != "ovbuddy" ]; then
    hostnamectl set-hostname ovbuddy 2>/dev/null || true
    log "✓ Set hostname to ovbuddy"
fi

# IMPORTANT: Do NOT run package installs/updates on boot.
# If avahi-daemon is missing, log a warning and exit quickly.
if ! command -v avahi-daemon >/dev/null 2>&1; then
    log "⚠ avahi-daemon not found. Install it manually: sudo apt-get install -y avahi-daemon"
    exit 0
fi

# Unmask avahi-daemon in case it was masked
systemctl unmask avahi-daemon 2>/dev/null || true
log "✓ Unmasked avahi-daemon (if it was masked)"

# Ensure avahi-daemon is enabled to start on boot
if systemctl is-enabled avahi-daemon >/dev/null 2>&1; then
    log "✓ avahi-daemon is already enabled"
else
    systemctl enable avahi-daemon 2>/dev/null || true
    log "✓ Enabled avahi-daemon to start on boot"
fi

# Start or restart avahi-daemon to pick up changes (best-effort, non-blocking)
if systemctl is-active avahi-daemon >/dev/null 2>&1; then
    # Already running, restart it
    systemctl restart avahi-daemon 2>/dev/null || true
    log "✓ Restarted avahi-daemon"
else
    # Not running, start it
    systemctl start avahi-daemon 2>/dev/null || true
    log "✓ Started avahi-daemon"
fi

# Don't wait here; boot speed matters more than synchronous verification.
log "✓ Bonjour/mDNS fix complete (triggered avahi-daemon start/restart)"

# Always exit successfully so we don't block the boot process
exit 0

