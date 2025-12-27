#!/bin/bash

# Unified script to install all OVBuddy services
# This script installs:
# - fix-bonjour.service (avahi-daemon boot fix)
# - ovbuddy.service (display service)
# - ovbuddy-web.service (web interface)
# - ovbuddy-wifi.service (WiFi monitor with AP fallback) [optional]

set -e

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root (use sudo)"
    exit 1
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Installing OVBuddy Services"
echo "=========================================="
echo ""

# Function to install a service
install_service() {
    local service_file="$1"
    local service_name="$2"
    local service_path="/etc/systemd/system/${service_name}.service"
    
    if [ -f "$service_file" ]; then
        echo "Installing ${service_name}..."
        cp "$service_file" "$service_path"
        echo -e "${GREEN}✓ Copied ${service_name} to systemd${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠ ${service_file} not found, skipping${NC}"
        return 1
    fi
}

# Function to install WiFi monitor dependencies
install_wifi_dependencies() {
    echo ""
    echo "Checking WiFi monitor dependencies..."
    
    local packages_needed=""
    
    if ! command -v hostapd &> /dev/null; then
        packages_needed="$packages_needed hostapd"
    fi
    
    if ! command -v dnsmasq &> /dev/null; then
        packages_needed="$packages_needed dnsmasq"
    fi
    
    if [ -n "$packages_needed" ]; then
        echo "Installing required packages:$packages_needed"
        apt-get update -qq
        apt-get install -y $packages_needed
        
        # Disable services (managed by wifi-monitor.py)
        systemctl stop hostapd dnsmasq 2>/dev/null || true
        systemctl disable hostapd dnsmasq 2>/dev/null || true
        systemctl unmask hostapd 2>/dev/null || true
        
        echo -e "${GREEN}✓ WiFi dependencies installed${NC}"
    else
        echo -e "${GREEN}✓ WiFi dependencies already installed${NC}"
    fi
}

# Stop all services first
echo "Stopping services if running..."
systemctl stop ovbuddy 2>/dev/null || true
systemctl stop ovbuddy-web 2>/dev/null || true
systemctl stop ovbuddy-wifi 2>/dev/null || true
systemctl stop fix-bonjour 2>/dev/null || true

# Kill any stray processes
echo "Checking for stray processes..."
pkill -f "ovbuddy.py" 2>/dev/null || true
pkill -f "ovbuddy_web.py" 2>/dev/null || true
pkill -f "wifi-monitor.py" 2>/dev/null || true

# Wait for services to stop and GPIO to be released
echo "Waiting for services and GPIO to be released..."
sleep 5

echo ""
echo "Installing service files..."

# Install fix-bonjour service first (it needs to run before other services)
BONJOUR_INSTALLED=false
if [ -f "fix-bonjour.service" ] && [ -f "fix-bonjour-persistent.sh" ]; then
    echo "Installing fix-bonjour service..."
    
    # Copy the persistent script to /usr/local/bin
    cp fix-bonjour-persistent.sh /usr/local/bin/fix-bonjour-persistent.sh
    chmod +x /usr/local/bin/fix-bonjour-persistent.sh
    echo -e "${GREEN}✓ Copied fix-bonjour-persistent.sh to /usr/local/bin${NC}"
    
    # Install the service
    if install_service "fix-bonjour.service" "fix-bonjour"; then
        BONJOUR_INSTALLED=true
        
        # Install timer if it exists
        if [ -f "fix-bonjour.timer" ]; then
            cp fix-bonjour.timer /etc/systemd/system/
            echo -e "${GREEN}✓ Installed fix-bonjour.timer${NC}"
        fi
    fi
else
    echo -e "${YELLOW}⚠ fix-bonjour files not found, skipping${NC}"
fi

# Install main display service
OVBUDDY_INSTALLED=false
if install_service "ovbuddy.service" "ovbuddy"; then
    OVBUDDY_INSTALLED=true
fi

# Install web service
WEB_INSTALLED=false
if install_service "ovbuddy-web.service" "ovbuddy-web"; then
    WEB_INSTALLED=true
fi

# Install WiFi monitor service (optional)
WIFI_INSTALLED=false
if [ -f "wifi-monitor.py" ] && [ -f "ovbuddy-wifi.service" ]; then
    echo ""
    echo "WiFi monitor service detected..."
    
    # Check if AP fallback is enabled in config
    AP_ENABLED=true
    if [ -f "config.json" ]; then
        # Check if ap_fallback_enabled exists and is true
        if grep -q '"ap_fallback_enabled"' config.json; then
            AP_ENABLED=$(python3 -c "import json; print(json.load(open('config.json')).get('ap_fallback_enabled', True))" 2>/dev/null || echo "true")
        fi
    fi
    
    if [ "$AP_ENABLED" = "True" ] || [ "$AP_ENABLED" = "true" ]; then
        echo "AP fallback is enabled, installing WiFi monitor..."
        
        # Install dependencies
        install_wifi_dependencies
        
        # Make script executable
        chmod +x wifi-monitor.py
        
        # Install service
        if install_service "ovbuddy-wifi.service" "ovbuddy-wifi"; then
            WIFI_INSTALLED=true
        fi
    else
        echo -e "${YELLOW}⚠ AP fallback is disabled in config, skipping WiFi monitor${NC}"
        echo "  To enable: Set 'ap_fallback_enabled: true' in config.json"
    fi
else
    echo -e "${YELLOW}⚠ WiFi monitor files not found, skipping${NC}"
fi

# Reload systemd
echo ""
echo "Reloading systemd daemon..."
systemctl daemon-reload
echo -e "${GREEN}✓ Systemd daemon reloaded${NC}"

# Enable and start services (in correct order)
echo ""
echo "Enabling and starting services..."

# Start fix-bonjour first
if [ "$BONJOUR_INSTALLED" = true ]; then
    systemctl enable fix-bonjour
    echo "Starting fix-bonjour (best-effort; will not block install)..."
    systemctl start fix-bonjour --no-block 2>/dev/null || true
    echo -e "${GREEN}✓ fix-bonjour service enabled${NC}"
    
    # Enable timer if it exists
    if [ -f "/etc/systemd/system/fix-bonjour.timer" ]; then
        systemctl enable fix-bonjour.timer
        systemctl start fix-bonjour.timer
        echo -e "${GREEN}✓ fix-bonjour timer enabled and started${NC}"
    fi
fi

# Start WiFi monitor (before display and web services)
if [ "$WIFI_INSTALLED" = true ]; then
    systemctl enable ovbuddy-wifi
    systemctl start ovbuddy-wifi
    echo -e "${GREEN}✓ ovbuddy-wifi service enabled and started${NC}"
    sleep 1
fi

# Start display service
if [ "$OVBUDDY_INSTALLED" = true ]; then
    systemctl enable ovbuddy
    systemctl start ovbuddy
    echo -e "${GREEN}✓ ovbuddy service enabled and started${NC}"
fi

# Start web service
if [ "$WEB_INSTALLED" = true ]; then
    systemctl enable ovbuddy-web
    systemctl start ovbuddy-web
    echo -e "${GREEN}✓ ovbuddy-web service enabled and started${NC}"
fi

# Show status
echo ""
echo "=========================================="
echo "Service Status"
echo "=========================================="

if [ "$BONJOUR_INSTALLED" = true ]; then
    echo ""
    echo "Bonjour Fix Service:"
    systemctl status fix-bonjour --no-pager -l || true
    echo ""
    echo "Avahi-Daemon Status:"
    systemctl status avahi-daemon --no-pager -l || true
fi

if [ "$WIFI_INSTALLED" = true ]; then
    echo ""
    echo "WiFi Monitor Service:"
    systemctl status ovbuddy-wifi --no-pager -l || true
fi

if [ "$OVBUDDY_INSTALLED" = true ]; then
    echo ""
    echo "Display Service:"
    systemctl status ovbuddy --no-pager -l || true
fi

if [ "$WEB_INSTALLED" = true ]; then
    echo ""
    echo "Web Service:"
    systemctl status ovbuddy-web --no-pager -l || true
fi

echo ""
echo "=========================================="
echo "Installation Complete!"
echo "=========================================="
echo ""
echo "Installed services:"
[ "$BONJOUR_INSTALLED" = true ] && echo "  ✓ fix-bonjour (avahi-daemon boot fix)"
[ "$WIFI_INSTALLED" = true ] && echo "  ✓ ovbuddy-wifi (WiFi monitor with AP fallback)"
[ "$OVBUDDY_INSTALLED" = true ] && echo "  ✓ ovbuddy (display service)"
[ "$WEB_INSTALLED" = true ] && echo "  ✓ ovbuddy-web (web interface)"
echo ""
echo "Boot order:"
echo "  - Services start in parallel; the display is no longer blocked on WiFi 'online'."
echo "  - ovbuddy-wifi still starts before ovbuddy/ovbuddy-web to avoid display conflicts in AP mode."
echo ""
echo "Useful commands:"
[ "$BONJOUR_INSTALLED" = true ] && echo "  sudo systemctl status fix-bonjour       # Check Bonjour fix"
[ "$BONJOUR_INSTALLED" = true ] && echo "  sudo systemctl status avahi-daemon      # Check mDNS service"
[ "$WIFI_INSTALLED" = true ] && echo "  sudo systemctl status ovbuddy-wifi      # Check WiFi monitor"
echo "  sudo systemctl status ovbuddy           # Check display service"
echo "  sudo systemctl status ovbuddy-web       # Check web service"
echo ""
echo "View logs:"
[ "$BONJOUR_INSTALLED" = true ] && echo "  sudo journalctl -u fix-bonjour -f       # Bonjour fix logs"
[ "$WIFI_INSTALLED" = true ] && echo "  sudo journalctl -u ovbuddy-wifi -f      # WiFi monitor logs"
echo "  sudo journalctl -u ovbuddy -f           # Display logs"
echo "  sudo journalctl -u ovbuddy-web -f       # Web logs"
echo ""


