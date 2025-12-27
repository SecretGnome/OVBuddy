#!/bin/bash

# Diagnostic script to check Bonjour/mDNS setup on Raspberry Pi

echo "=== Bonjour/mDNS Diagnostic ==="
echo ""

# Check hostname
echo "1. Hostname:"
hostname
echo ""

# Check if hostname is set correctly
HOSTNAME=$(hostname)
if [ "$HOSTNAME" != "ovbuddy" ]; then
    echo "⚠ WARNING: Hostname is '$HOSTNAME', should be 'ovbuddy'"
    echo "  Fix with: sudo hostnamectl set-hostname ovbuddy"
    echo ""
fi

# Check /etc/hosts
echo "2. /etc/hosts entries (looking for .local):"
grep -i "\.local" /etc/hosts || echo "  ✓ No .local entries found"
echo ""

# Check avahi-daemon status
echo "3. avahi-daemon status:"
systemctl is-active avahi-daemon && echo "  ✓ avahi-daemon is running" || echo "  ✗ avahi-daemon is not running"
systemctl is-enabled avahi-daemon && echo "  ✓ avahi-daemon is enabled" || echo "  ✗ avahi-daemon is not enabled"
# Check if masked
if systemctl is-masked avahi-daemon 2>/dev/null; then
    echo "  ⚠ WARNING: avahi-daemon is MASKED (will not start even if enabled)"
    echo "    Fix with: sudo systemctl unmask avahi-daemon"
fi
echo ""
echo "  Recent avahi-daemon logs:"
journalctl -u avahi-daemon -n 5 --no-pager 2>/dev/null || echo "  (no logs available)"
echo ""

# Check fix-bonjour service status
echo "4. fix-bonjour service status:"
if systemctl list-unit-files | grep -q fix-bonjour.service; then
    systemctl is-active fix-bonjour.service && echo "  ✓ fix-bonjour service is active" || echo "  ✗ fix-bonjour service is not active"
    systemctl is-enabled fix-bonjour.service && echo "  ✓ fix-bonjour service is enabled" || echo "  ✗ fix-bonjour service is not enabled"
    echo ""
    echo "  Recent logs:"
    journalctl -u fix-bonjour.service -n 10 --no-pager || true
else
    echo "  ✗ fix-bonjour.service not found"
fi
echo ""

# Check fix-bonjour timer status
echo "5. fix-bonjour timer status:"
if systemctl list-unit-files | grep -q fix-bonjour.timer; then
    systemctl is-active fix-bonjour.timer && echo "  ✓ fix-bonjour timer is active" || echo "  ✗ fix-bonjour timer is not active"
    systemctl is-enabled fix-bonjour.timer && echo "  ✓ fix-bonjour timer is enabled" || echo "  ✗ fix-bonjour timer is not enabled"
    echo ""
    echo "  Next run:"
    systemctl list-timers fix-bonjour.timer --no-pager || true
else
    echo "  ✗ fix-bonjour.timer not found"
fi
echo ""

# Check avahi-daemon configuration
echo "6. avahi-daemon configuration:"
if [ -f /etc/avahi/avahi-daemon.conf ]; then
    echo "  Checking /etc/avahi/avahi-daemon.conf:"
    grep -E "^host-name|^domain-name|^publish-hinfo|^publish-workstation" /etc/avahi/avahi-daemon.conf || echo "  Using defaults"
else
    echo "  ⚠ /etc/avahi/avahi-daemon.conf not found"
fi
echo ""

# Test mDNS resolution locally
echo "7. Testing mDNS resolution on Pi:"
if command -v avahi-resolve >/dev/null 2>&1; then
    avahi-resolve -n ${HOSTNAME}.local 2>/dev/null && echo "  ✓ ${HOSTNAME}.local resolves locally" || echo "  ✗ ${HOSTNAME}.local does not resolve locally"
else
    getent hosts ${HOSTNAME}.local 2>/dev/null && echo "  ✓ ${HOSTNAME}.local resolves locally" || echo "  ✗ ${HOSTNAME}.local does not resolve locally"
fi
echo ""

# Check IP address
echo "8. IP address:"
hostname -I | awk '{print $1}'
echo ""

echo "=== End Diagnostic ==="



