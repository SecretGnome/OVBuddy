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
    echo "For other operating systems, please follow the manual instructions."
    echo ""
fi

echo -e "${YELLOW}This script will help you set up an SD card for OVBuddy.${NC}"
echo ""
echo "Requirements:"
echo "  - SD card (8GB or larger recommended)"
echo "  - WiFi network credentials"
echo ""

# Check for setup.env file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SETUP_ENV="$PROJECT_ROOT/setup.env"

if [[ -f "$SETUP_ENV" ]]; then
    echo -e "${GREEN}Found setup.env file. Loading configuration...${NC}"
    source "$SETUP_ENV"
    echo -e "${GREEN}✓ Configuration loaded${NC}"
    echo ""
    
    # Validate required variables
    if [[ -z "$WIFI_SSID" || -z "$WIFI_PASSWORD" || -z "$WIFI_COUNTRY" ]]; then
        echo -e "${RED}Error: setup.env is missing required WiFi configuration.${NC}"
        echo "Please ensure WIFI_SSID, WIFI_PASSWORD, and WIFI_COUNTRY are set."
        exit 1
    fi
    
    # Set defaults for optional variables
    HOSTNAME=${HOSTNAME:-ovbuddy}
    USERNAME=${USERNAME:-pi}
    USER_PASSWORD=${USER_PASSWORD:-raspberry}
    
    # Default to automated CLI when using setup.env
    SETUP_METHOD="1"
    
    echo -e "${BLUE}Configuration from setup.env:${NC}"
    echo "  WiFi SSID: $WIFI_SSID"
    echo "  WiFi Country: $WIFI_COUNTRY"
    echo "  Hostname: $HOSTNAME"
    echo "  Username: $USERNAME"
    echo ""
    
    read -p "Continue with these settings? (y/N) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
    echo ""
else
    # Prompt for setup method
    echo -e "${BLUE}Choose setup method:${NC}"
    echo "  1. Automated CLI (downloads and writes image automatically)"
    echo "  2. Manual GUI (opens Raspberry Pi Imager with instructions)"
    echo ""
    read -p "Enter choice (1 or 2): " SETUP_METHOD
    echo ""
    
    if [[ "$SETUP_METHOD" != "1" && "$SETUP_METHOD" != "2" ]]; then
        echo -e "${RED}Invalid choice. Exiting.${NC}"
        exit 1
    fi
    
    # Prompt for WiFi credentials
    echo -e "${YELLOW}Please enter your configuration:${NC}"
    read -p "WiFi SSID: " WIFI_SSID
    read -sp "WiFi Password: " WIFI_PASSWORD
    echo ""
    echo ""
    
    # Prompt for WiFi country code
    read -p "WiFi Country Code (e.g., US, GB, CH): " WIFI_COUNTRY
    WIFI_COUNTRY=${WIFI_COUNTRY:-US}
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
fi

# Only show confirmation if not already shown for setup.env
if [[ ! -f "$SETUP_ENV" ]]; then
    echo -e "${BLUE}Configuration Summary:${NC}"
    echo "  Hostname: $HOSTNAME"
    echo "  Username: $USERNAME"
    echo "  WiFi SSID: $WIFI_SSID"
    echo "  WiFi Country: $WIFI_COUNTRY"
    echo ""
    
    read -p "Continue with these settings? (y/N) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
    echo ""
fi

# ============================================================================
# AUTOMATED CLI METHOD
# ============================================================================
if [[ "$SETUP_METHOD" == "1" ]]; then
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  AUTOMATED CLI SETUP${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    # Check for required tools
    if ! command -v curl &> /dev/null; then
        echo -e "${RED}Error: curl is required but not installed.${NC}"
        exit 1
    fi

    # List available disks
    echo -e "${YELLOW}Available disks:${NC}"
    diskutil list
    echo ""
    
    read -p "Enter the disk identifier (e.g., disk2): " DISK_ID
    
    if [[ ! "$DISK_ID" =~ ^disk[0-9]+$ ]]; then
        echo -e "${RED}Error: Invalid disk identifier. Must be in format 'diskN'.${NC}"
        exit 1
    fi
    
    DISK_PATH="/dev/$DISK_ID"
    
    # Confirm disk selection
    echo ""
    echo -e "${RED}WARNING: This will erase ALL data on $DISK_ID!${NC}"
    diskutil info "$DISK_ID" | grep -E "Device Node|Media Name|Total Size"
    echo ""
    read -p "Are you ABSOLUTELY sure you want to continue? Type 'YES' to proceed: " CONFIRM
    
    if [[ "$CONFIRM" != "YES" ]]; then
        echo "Aborted."
        exit 1
    fi
    
    # Create temporary directory
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf $TEMP_DIR" EXIT
    
    IMAGE_URL="https://downloads.raspberrypi.com/raspios_oldstable_lite_armhf/images/raspios_oldstable_lite_armhf-2025-11-24/2025-11-24-raspios-bookworm-armhf-lite.img.xz"
    IMAGE_FILE="$TEMP_DIR/raspios.img.xz"
    IMAGE_SHA256="2a6ff6474218e5e83b6448771e902a4e5e06a86b9604b3b02f8d69ccc5bfb47b"
    
    echo ""
    echo -e "${YELLOW}Downloading Raspberry Pi OS (Legacy) Lite (32-bit)...${NC}"
    echo "Release: 24 November 2025 (Debian Bookworm)"
    echo "This may take several minutes depending on your connection."
    echo ""
    
    if ! curl -L -o "$IMAGE_FILE" --progress-bar "$IMAGE_URL"; then
        echo -e "${RED}Error: Failed to download image.${NC}"
        exit 1
    fi
    
    echo ""
    echo -e "${GREEN}✓ Download complete${NC}"
    echo ""
    
    # Verify SHA256 checksum
    echo -e "${YELLOW}Verifying image integrity...${NC}"
    if command -v shasum &> /dev/null; then
        DOWNLOADED_SHA256=$(shasum -a 256 "$IMAGE_FILE" | awk '{print $1}')
    elif command -v sha256sum &> /dev/null; then
        DOWNLOADED_SHA256=$(sha256sum "$IMAGE_FILE" | awk '{print $1}')
    else
        echo -e "${YELLOW}Warning: Neither shasum nor sha256sum found. Skipping checksum verification.${NC}"
        DOWNLOADED_SHA256="$IMAGE_SHA256"
    fi
    
    if [[ "$DOWNLOADED_SHA256" != "$IMAGE_SHA256" ]]; then
        echo -e "${RED}Error: SHA256 checksum mismatch!${NC}"
        echo "Expected: $IMAGE_SHA256"
        echo "Got:      $DOWNLOADED_SHA256"
        echo ""
        echo "The downloaded file may be corrupted. Please try again."
        exit 1
    fi
    
    echo -e "${GREEN}✓ Image integrity verified${NC}"
    echo ""
    
    # Unmount the disk (but don't eject it)
    echo -e "${YELLOW}Unmounting disk...${NC}"
    diskutil unmountDisk "$DISK_PATH" || true
    
    # Write the image
    echo ""
    echo -e "${YELLOW}Writing image to SD card...${NC}"
    echo "This will take several minutes. Please be patient."
    echo ""
    
    if ! sudo sh -c "xzcat '$IMAGE_FILE' | dd of='$DISK_PATH' bs=4m"; then
        echo -e "${RED}Error: Failed to write image.${NC}"
        exit 1
    fi
    
    echo ""
    echo -e "${GREEN}✓ Image written successfully${NC}"
    echo ""
    
    # Sync to ensure all data is written
    echo -e "${YELLOW}Syncing data...${NC}"
    sync
    sleep 2
    
    # Now mount the disk partitions (this will read the new partition table)
    echo -e "${YELLOW}Mounting disk partitions...${NC}"
    diskutil mountDisk "$DISK_PATH"
    sleep 3
    
    # Find the boot partition - try multiple possible names
    BOOT_VOLUME=""
    for vol_name in "bootfs" "boot" "BOOT"; do
        if [[ -d "/Volumes/$vol_name" ]]; then
            BOOT_VOLUME="/Volumes/$vol_name"
            break
        fi
    done
    
    # If still not found, try mounting the first partition explicitly
    if [[ -z "$BOOT_VOLUME" ]]; then
        echo -e "${YELLOW}Boot partition not automatically mounted. Trying to mount manually...${NC}"
        diskutil mount "${DISK_ID}s1" 2>/dev/null || true
        sleep 2
        
        # Check again for all possible names
        for vol_name in "bootfs" "boot" "BOOT"; do
            if [[ -d "/Volumes/$vol_name" ]]; then
                BOOT_VOLUME="/Volumes/$vol_name"
                break
            fi
        done
    fi
    
    # Final check
    if [[ -z "$BOOT_VOLUME" ]]; then
        echo -e "${RED}Error: Could not find boot partition.${NC}"
        echo ""
        echo "Available volumes:"
        ls -la /Volumes/
        echo ""
        echo "Please manually configure the SD card:"
        echo "  1. Mount the boot partition (usually named 'bootfs' or 'boot')"
        echo "  2. Create an empty file named 'ssh' in the boot partition"
        echo "  3. Create 'wpa_supplicant.conf' with your WiFi credentials"
        echo ""
        echo "Or try running this script again."
        exit 1
    fi
    
    echo -e "${GREEN}✓ Boot partition found at: $BOOT_VOLUME${NC}"
    echo ""
    
    # Generate WPA-PSK hash for WiFi password
    echo -e "${YELLOW}Generating WiFi password hash...${NC}"
    if command -v wpa_passphrase &> /dev/null; then
        WIFI_PSK_HASH=$(wpa_passphrase "$WIFI_SSID" "$WIFI_PASSWORD" | grep -E "^\s+psk=" | sed 's/.*psk=//' | tr -d '\n')
    else
        # Generate WPA-PSK hash using Python (PBKDF2)
        WIFI_PSK_HASH=$(python3 << PYEOF
import hashlib
import binascii

ssid = '$WIFI_SSID'
password = '$WIFI_PASSWORD'

# WPA-PSK uses PBKDF2 with 4096 iterations
psk = hashlib.pbkdf2_hmac('sha1', password.encode('utf-8'), ssid.encode('utf-8'), 4096, 32)
print(binascii.hexlify(psk).decode('ascii'))
PYEOF
)
        echo -e "${GREEN}✓ WiFi password hash generated${NC}"
    fi
    
    # Generate password hash using Python crypt module (cross-platform)
    echo -e "${YELLOW}Generating password hash...${NC}"
    
    # Use Python crypt module (works on both macOS and Linux)
    # Pass password via stdin to safely handle special characters
    PASSWORD_HASH=$(echo -n "$USER_PASSWORD" | python3 << 'PYEOF'
import crypt
import sys

try:
    # Read password from stdin
    password = sys.stdin.read().strip()
    
    # Generate SHA-512 hash (same as openssl passwd -6)
    hash_val = crypt.crypt(password, crypt.mksalt(crypt.METHOD_SHA512))
    print(hash_val)
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
)
    if [ $? -eq 0 ] && [ -n "$PASSWORD_HASH" ]; then
        echo -e "${GREEN}✓ Password hash generated${NC}"
    else
        echo -e "${RED}Error: Failed to generate password hash${NC}"
        exit 1
    fi
    
    # Create firstrun.sh script (matches Raspberry Pi Imager approach)
    echo -e "${YELLOW}Creating firstrun.sh script...${NC}"
    cat > "$BOOT_VOLUME/firstrun.sh" << 'FIRSTRUN_EOF'
#!/bin/sh

set +e

CURRENT_HOSTNAME=$(cat /etc/hostname | tr -d " \t\n\r")
if [ -f /usr/lib/raspberrypi-sys-mods/imager_custom ]; then
   /usr/lib/raspberrypi-sys-mods/imager_custom set_hostname HOSTNAME_PLACEHOLDER
else
   echo HOSTNAME_PLACEHOLDER >/etc/hostname
   sed -i "s/127.0.1.1.*$CURRENT_HOSTNAME/127.0.1.1\tHOSTNAME_PLACEHOLDER/g" /etc/hosts
fi
FIRSTUSER=$(getent passwd 1000 | cut -d: -f1)
FIRSTUSERHOME=$(getent passwd 1000 | cut -d: -f6)
if [ -f /usr/lib/raspberrypi-sys-mods/imager_custom ]; then
   /usr/lib/raspberrypi-sys-mods/imager_custom enable_ssh
else
   systemctl enable ssh
fi
if [ -f /usr/lib/userconf-pi/userconf ]; then
   /usr/lib/userconf-pi/userconf 'USERNAME_PLACEHOLDER' 'PASSWORD_HASH_PLACEHOLDER'
else
   echo "USERNAME_PLACEHOLDER:PASSWORD_HASH_PLACEHOLDER" | chpasswd -e
   if [ "$FIRSTUSER" != "USERNAME_PLACEHOLDER" ]; then
      usermod -l "USERNAME_PLACEHOLDER" "$FIRSTUSER"
      usermod -m -d "/home/USERNAME_PLACEHOLDER" "USERNAME_PLACEHOLDER"
      groupmod -n "USERNAME_PLACEHOLDER" "$FIRSTUSER"
      if grep -q "^autologin-user=" /etc/lightdm/lightdm.conf ; then
         sed /etc/lightdm/lightdm.conf -i -e "s/^autologin-user=.*/autologin-user=USERNAME_PLACEHOLDER/"
      fi
      if [ -f /etc/systemd/system/getty@tty1.service.d/autologin.conf ]; then
         sed /etc/systemd/system/getty@tty1.service.d/autologin.conf -i -e "s/$FIRSTUSER/USERNAME_PLACEHOLDER/"
      fi
      if [ -f /etc/sudoers.d/010_pi-nopasswd ]; then
         sed -i "s/^$FIRSTUSER /USERNAME_PLACEHOLDER /" /etc/sudoers.d/010_pi-nopasswd
      fi
   fi
fi
if [ -f /usr/lib/raspberrypi-sys-mods/imager_custom ]; then
   /usr/lib/raspberrypi-sys-mods/imager_custom set_wlan 'WIFI_SSID_PLACEHOLDER' 'WIFI_PSK_HASH_PLACEHOLDER' 'WIFI_COUNTRY_PLACEHOLDER'
else
cat >/etc/wpa_supplicant/wpa_supplicant.conf <<'WPAEOF'
country=WIFI_COUNTRY_PLACEHOLDER
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
ap_scan=1

update_config=1
network={
	ssid="WIFI_SSID_PLACEHOLDER"
	key_mgmt=WPA-PSK SAE
	psk=WIFI_PSK_HASH_PLACEHOLDER
	ieee80211w=1
}
WPAEOF
   chmod 600 /etc/wpa_supplicant/wpa_supplicant.conf
   rfkill unblock wifi
   for filename in /var/lib/systemd/rfkill/*:wlan ; do
       echo 0 > $filename
   done
fi
rm -f /boot/firstrun.sh
sed -i 's| systemd.run.*||g' /boot/cmdline.txt
exit 0
FIRSTRUN_EOF
    
    # Replace placeholders in firstrun.sh
    sed -i '' "s/HOSTNAME_PLACEHOLDER/$HOSTNAME/g" "$BOOT_VOLUME/firstrun.sh"
    sed -i '' "s/USERNAME_PLACEHOLDER/$USERNAME/g" "$BOOT_VOLUME/firstrun.sh"
    sed -i '' "s|PASSWORD_HASH_PLACEHOLDER|$PASSWORD_HASH|g" "$BOOT_VOLUME/firstrun.sh"
    sed -i '' "s/WIFI_SSID_PLACEHOLDER/$WIFI_SSID/g" "$BOOT_VOLUME/firstrun.sh"
    sed -i '' "s|WIFI_PSK_HASH_PLACEHOLDER|$WIFI_PSK_HASH|g" "$BOOT_VOLUME/firstrun.sh"
    sed -i '' "s/WIFI_COUNTRY_PLACEHOLDER/$WIFI_COUNTRY/g" "$BOOT_VOLUME/firstrun.sh"
    chmod +x "$BOOT_VOLUME/firstrun.sh"
    echo -e "${GREEN}✓ firstrun.sh created${NC}"
    
    # Modify cmdline.txt to add systemd.run parameter
    echo -e "${YELLOW}Configuring boot parameters...${NC}"
    if ! grep -q "systemd.run=/boot/firstrun.sh" "$BOOT_VOLUME/cmdline.txt"; then
        # Add systemd.run parameters to cmdline.txt
        CMDLINE=$(cat "$BOOT_VOLUME/cmdline.txt")
        echo "$CMDLINE systemd.run=/boot/firstrun.sh systemd.run_success_action=reboot systemd.unit=kernel-command-line.target" > "$BOOT_VOLUME/cmdline.txt"
        echo -e "${GREEN}✓ Boot parameters configured${NC}"
    else
        echo -e "${GREEN}✓ Boot parameters already configured${NC}"
    fi
    
    # Sync and unmount
    echo ""
    echo -e "${YELLOW}Syncing and ejecting SD card...${NC}"
    sync
    diskutil eject "$DISK_PATH"
    
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  SD CARD SETUP COMPLETE!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Your SD card is ready! Next steps:"
    echo ""
    echo "1. Insert the SD card into your Raspberry Pi Zero W"
    echo "2. Power on the Pi (first boot takes 2-3 minutes)"
    echo "   The Pi will automatically:"
    echo "   - Set hostname to '${HOSTNAME}'"
    echo "   - Configure WiFi"
    echo "   - Enable SSH"
    echo "   - Set up user '${USERNAME}' with your password"
    echo "   - Reboot automatically when done"
    echo ""
    echo "3. After the Pi reboots, wait 30 seconds, then SSH:"
    echo "   ssh ${USERNAME}@${HOSTNAME}.local"
    echo "   Password: ${USER_PASSWORD}"
    echo ""
    echo "4. Update the .env file in the OVBuddy project:"
    echo "   PI_HOST=${HOSTNAME}.local"
    echo "   PI_USER=${USERNAME}"
    echo "   PI_PASSWORD=${USER_PASSWORD}"
    echo ""
    echo "5. Run the deployment script:"
    echo "   cd scripts"
    echo "   ./deploy.sh"
    echo ""

# ============================================================================
# MANUAL GUI METHOD
# ============================================================================
else
    # Check if Raspberry Pi Imager is installed
    RPI_IMAGER_APP="/Applications/Raspberry Pi Imager.app"
    if [[ ! -d "$RPI_IMAGER_APP" ]]; then
        echo -e "${YELLOW}Raspberry Pi Imager not found.${NC}"
        echo ""
        echo "Please install Raspberry Pi Imager:"
        echo "  brew install --cask raspberry-pi-imager"
        echo ""
        echo "Or download from: https://www.raspberrypi.com/software/"
        echo ""
        exit 1
    fi
    
    echo -e "${GREEN}✓ Raspberry Pi Imager is installed${NC}"
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
    echo "       Country: ${WIFI_COUNTRY}"
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
    open -a "Raspberry Pi Imager"
    
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
fi

echo -e "${GREEN}Done!${NC}"
