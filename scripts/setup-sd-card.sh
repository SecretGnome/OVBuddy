#!/bin/bash

# Script to setup an SD card with Raspberry Pi OS Lite for OVBuddy
# This script helps prepare an SD card for Raspberry Pi Zero W 1.1

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          OVBuddy SD Card Setup Helper                      ║${NC}"
echo -e "${BLUE}║     For Raspberry Pi Zero W 1.1 with RPi OS Lite          ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo -e "${YELLOW}Warning: This script is designed for macOS.${NC}"
    echo "For other operating systems, please use Raspberry Pi Imager manually."
    echo ""
fi

echo -e "${YELLOW}This script will guide you through setting up an SD card for OVBuddy.${NC}"
echo ""
echo "Requirements:"
echo "  - SD card (8GB or larger recommended)"
echo "  - Raspberry Pi Imager installed"
echo "  - WiFi network credentials"
echo ""

# Check if Raspberry Pi Imager is installed
if ! command -v rpi-imager &> /dev/null; then
    echo -e "${YELLOW}Raspberry Pi Imager not found.${NC}"
    echo ""
    echo "Please install Raspberry Pi Imager:"
    echo "  1. Visit: https://www.raspberrypi.com/software/"
    echo "  2. Download and install Raspberry Pi Imager"
    echo "  3. Run this script again"
    echo ""
    echo "Or install via Homebrew:"
    echo "  brew install --cask raspberry-pi-imager"
    echo ""
    exit 1
fi

echo -e "${GREEN}✓ Raspberry Pi Imager is installed${NC}"
echo ""

# Prompt for WiFi credentials
echo -e "${YELLOW}Please enter your WiFi credentials:${NC}"
read -p "WiFi SSID: " WIFI_SSID
read -sp "WiFi Password: " WIFI_PASSWORD
echo ""
echo ""

# Prompt for hostname
read -p "Hostname (default: ovbuddy): " HOSTNAME
HOSTNAME=${HOSTNAME:-ovbuddy}
echo ""

# Prompt for username
read -p "Username (default: pi): " USERNAME
USERNAME=${USERNAME:-pi}
echo ""

# Prompt for password
read -sp "User Password: " USER_PASSWORD
echo ""
echo ""

echo -e "${BLUE}Configuration Summary:${NC}"
echo "  Hostname: $HOSTNAME"
echo "  Username: $USERNAME"
echo "  WiFi SSID: $WIFI_SSID"
echo ""

read -p "Continue with these settings? (y/N) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  MANUAL SETUP INSTRUCTIONS${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo "1. Launch Raspberry Pi Imager"
echo ""
echo "2. Click 'CHOOSE DEVICE' and select:"
echo "   → Raspberry Pi Zero W"
echo ""
echo "3. Click 'CHOOSE OS' and select:"
echo "   → Raspberry Pi OS (other)"
echo "   → Raspberry Pi OS Lite (32-bit)"
echo "   → Use the LEGACY version (Debian Bullseye)"
echo ""
echo "4. Click 'CHOOSE STORAGE' and select your SD card"
echo ""
echo "5. Click the gear icon (⚙️) or 'EDIT SETTINGS' to configure:"
echo ""
echo "   General Settings:"
echo "   ✓ Set hostname: ${HOSTNAME}"
echo "   ✓ Set username and password:"
echo "       Username: ${USERNAME}"
echo "       Password: [your password]"
echo "   ✓ Configure wireless LAN:"
echo "       SSID: ${WIFI_SSID}"
echo "       Password: [your WiFi password]"
echo "       Country: [your country code, e.g., CH for Switzerland]"
echo "   ✓ Set locale settings:"
echo "       Time zone: [your timezone]"
echo "       Keyboard layout: [your layout]"
echo ""
echo "   Services:"
echo "   ✓ Enable SSH"
echo "   ✓ Use password authentication"
echo ""
echo "6. Click 'SAVE' to save the settings"
echo ""
echo "7. Click 'WRITE' to write the image to the SD card"
echo ""
echo "8. Wait for the write and verification to complete"
echo ""
echo "9. Eject the SD card and insert it into your Raspberry Pi Zero W"
echo ""
echo "10. Power on the Raspberry Pi and wait for it to boot (first boot takes longer)"
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo ""

read -p "Press Enter to launch Raspberry Pi Imager..." -r
echo ""

# Launch Raspberry Pi Imager
echo "Launching Raspberry Pi Imager..."
open -a "Raspberry Pi Imager" || rpi-imager &

echo ""
echo -e "${GREEN}After the SD card is ready and the Pi is booted:${NC}"
echo ""
echo "1. Test SSH connection:"
echo "   ssh ${USERNAME}@${HOSTNAME}.local"
echo ""
echo "2. Update the .env file in the OVBuddy project:"
echo "   PI_HOST=${HOSTNAME}.local"
echo "   PI_USER=${USERNAME}"
echo "   PI_PASSWORD=[your password]"
echo ""
echo "3. Run the deployment script:"
echo "   cd scripts"
echo "   ./deploy.sh"
echo ""
echo "4. Setup passwordless sudo (optional but recommended):"
echo "   ./setup-passwordless-sudo.sh"
echo ""
echo -e "${GREEN}Done! Your SD card will be ready after imaging completes.${NC}"

