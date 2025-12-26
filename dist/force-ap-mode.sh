#!/bin/bash

# Force Access Point Mode
# This script forces the device into AP mode by creating a flag file and rebooting
# After reboot, wifi-monitor will detect the flag and enter AP mode immediately

set -e

echo "Forcing Access Point Mode..."
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "This script must be run as root (use sudo)"
    exit 1
fi

# Create force AP flag file (in /var/lib which persists across reboots)
FORCE_AP_FLAG="/var/lib/ovbuddy-force-ap"
echo "Creating force AP flag..."
touch "$FORCE_AP_FLAG"
echo "  ✓ Flag created at $FORCE_AP_FLAG"

# Detect WiFi manager and prevent auto-reconnect
echo "Preventing WiFi auto-reconnect..."

# Check if NetworkManager is managing WiFi
if command -v nmcli &> /dev/null; then
    NM_STATUS=$(nmcli device status 2>/dev/null | grep wlan0 || true)
    if [ -n "$NM_STATUS" ] && ! echo "$NM_STATUS" | grep -q "unmanaged"; then
        echo "  Detected NetworkManager, disabling auto-connect..."
        
        # Disconnect from current network
        nmcli device disconnect wlan0 2>/dev/null || true
        
        # Disable auto-connect for all WiFi connections
        for conn in $(nmcli -t -f NAME,TYPE connection show | grep ':802-11-wireless$' | cut -d: -f1); do
            echo "    Disabling auto-connect for: $conn"
            nmcli connection modify "$conn" connection.autoconnect no 2>/dev/null || true
        done
        
        # Set wlan0 to unmanaged temporarily (will be re-enabled by wifi-monitor)
        nmcli device set wlan0 managed no 2>/dev/null || true
        
        echo "  ✓ Auto-connect disabled (NetworkManager)"
    else
        # Try wpa_cli
        echo "  Using wpa_supplicant method..."
        wpa_cli -i wlan0 disconnect 2>/dev/null || true
        wpa_cli -i wlan0 disable_network all 2>/dev/null || true
        wpa_cli -i wlan0 save_config 2>/dev/null || true
        echo "  ✓ Networks disabled (wpa_supplicant)"
    fi
else
    # Try wpa_cli
    echo "  Using wpa_supplicant method..."
    wpa_cli -i wlan0 disconnect 2>/dev/null || true
    wpa_cli -i wlan0 disable_network all 2>/dev/null || true
    wpa_cli -i wlan0 save_config 2>/dev/null || true
    echo "  ✓ Networks disabled (wpa_supplicant)"
fi

echo ""
echo "✓ Force AP mode configured successfully"
echo ""
echo "The device will now reboot and enter Access Point mode immediately."
echo ""
echo "After reboot, the device will create an access point with:"
echo "  - SSID from config.json (default: OVBuddy)"
echo "  - Password from config.json (or open network if no password)"
echo "  - Web interface at: http://192.168.4.1:8080"
echo ""
echo "Your WiFi configuration will be preserved."
echo "You can reconnect to your WiFi network from the web interface."
echo ""
echo "Rebooting in 3 seconds..."
sleep 3

# Reboot the device
reboot
