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

usage() {
    cat << 'EOF'
OVBuddy SD Card Setup Helper

Usage:
  ./setup-sd-card.sh

Automation / non-interactive options:
  --disk <diskN>        Target disk identifier (example: disk2)
  --yes                 Skip confirmations (requires --disk for safety)
  --method <1|2>        Setup method: 1 = Automated CLI, 2 = Manual GUI (Raspberry Pi Imager)
  --pi-model <zero|4>   Raspberry Pi model: zero (Pi Zero W) or 4 (Pi 4) [default: zero]
  --os-variant <lite|full> OS variant: lite or full [default: lite]
  -h, --help            Show this help

Notes:
  - If `.env` exists, WiFi/hostname/user/password are loaded from it.
  - The automated CLI method is destructive: it will erase the target disk.
  - Pi Zero W uses 32-bit images, Pi 4 can use 32-bit or 64-bit (defaults to 64-bit for full, 32-bit for lite)
EOF
}

# Optional automation flags (defaults preserve existing interactive behavior)
DISK_ID_ARG=""
ASSUME_YES=false
METHOD_ARG=""
PI_MODEL_ARG=""
OS_VARIANT_ARG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --disk)
            shift
            DISK_ID_ARG="${1:-}"
            ;;
        --yes)
            ASSUME_YES=true
            ;;
        --method)
            shift
            METHOD_ARG="${1:-}"
            ;;
        --pi-model)
            shift
            PI_MODEL_ARG="${1:-}"
            ;;
        --os-variant)
            shift
            OS_VARIANT_ARG="${1:-}"
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo -e "${RED}Error: Unknown option: $1${NC}"
            echo ""
            usage
            exit 2
            ;;
        *)
            # No positional args supported
            ;;
    esac
    shift || true
done

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          OVBuddy SD Card Setup Helper                      ║${NC}"
echo -e "${BLUE}║     Supports Pi Zero W and Pi 4, Lite and Full OS         ║${NC}"
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

# Select Pi model
PI_MODEL=""
if [[ -n "$PI_MODEL_ARG" ]]; then
    PI_MODEL="$PI_MODEL_ARG"
    if [[ "$PI_MODEL" != "zero" && "$PI_MODEL" != "4" ]]; then
        echo -e "${RED}Error: --pi-model must be 'zero' or '4'${NC}"
        exit 1
    fi
else
    echo -e "${BLUE}Select Raspberry Pi model:${NC}"
    echo "  1. Raspberry Pi Zero W (32-bit only)"
    echo "  2. Raspberry Pi 4 (32-bit or 64-bit)"
    echo ""
    read -p "Enter choice (1 or 2, default: 1): " PI_CHOICE
    PI_CHOICE=${PI_CHOICE:-1}
    
    if [[ "$PI_CHOICE" == "1" ]]; then
        PI_MODEL="zero"
    elif [[ "$PI_CHOICE" == "2" ]]; then
        PI_MODEL="4"
    else
        echo -e "${RED}Invalid choice. Exiting.${NC}"
        exit 1
    fi
    echo ""
fi

# Select OS variant
OS_VARIANT=""
if [[ -n "$OS_VARIANT_ARG" ]]; then
    OS_VARIANT="$OS_VARIANT_ARG"
    if [[ "$OS_VARIANT" != "lite" && "$OS_VARIANT" != "full" ]]; then
        echo -e "${RED}Error: --os-variant must be 'lite' or 'full'${NC}"
        exit 1
    fi
else
    echo -e "${BLUE}Select OS variant:${NC}"
    echo "  1. Lite (minimal, no desktop environment)"
    echo "  2. Full (includes desktop environment)"
    echo ""
    read -p "Enter choice (1 or 2, default: 1): " OS_CHOICE
    OS_CHOICE=${OS_CHOICE:-1}
    
    if [[ "$OS_CHOICE" == "1" ]]; then
        OS_VARIANT="lite"
    elif [[ "$OS_CHOICE" == "2" ]]; then
        OS_VARIANT="full"
    else
        echo -e "${RED}Invalid choice. Exiting.${NC}"
        exit 1
    fi
    echo ""
fi

# Determine architecture based on Pi model and OS variant
# Pi Zero W: 32-bit only (armhf)
# Pi 4: 64-bit for full (arm64), 32-bit for lite (armhf) by default, but allow 64-bit lite too
ARCH="armhf"
if [[ "$PI_MODEL" == "4" && "$OS_VARIANT" == "full" ]]; then
    # Pi 4 Full defaults to 64-bit
    ARCH="arm64"
elif [[ "$PI_MODEL" == "4" && "$OS_VARIANT" == "lite" ]]; then
    # Pi 4 Lite: ask if user wants 64-bit
    if [[ -z "$OS_VARIANT_ARG" ]]; then
        echo -e "${BLUE}Select architecture for Pi 4 Lite:${NC}"
        echo "  1. 32-bit (armhf) - recommended for compatibility"
        echo "  2. 64-bit (arm64) - better performance"
        echo ""
        read -p "Enter choice (1 or 2, default: 1): " ARCH_CHOICE
        ARCH_CHOICE=${ARCH_CHOICE:-1}
        
        if [[ "$ARCH_CHOICE" == "2" ]]; then
            ARCH="arm64"
        fi
        echo ""
    else
        # Non-interactive: default to 32-bit for lite
        ARCH="armhf"
    fi
fi

# Display selection summary
echo -e "${GREEN}Selected configuration:${NC}"
echo "  Pi Model: Raspberry Pi $([ "$PI_MODEL" == "zero" ] && echo "Zero W" || echo "4")"
echo "  OS Variant: $([ "$OS_VARIANT" == "lite" ] && echo "Lite" || echo "Full")"
echo "  Architecture: $ARCH"
echo ""

# Check for .env file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"

if [[ -f "$ENV_FILE" ]]; then
    echo -e "${GREEN}Found .env file. Loading configuration...${NC}"
    source "$ENV_FILE"
    echo -e "${GREEN}✓ Configuration loaded${NC}"
    echo ""
    
    # Validate required variables
    if [[ -z "$WIFI_SSID" || -z "$WIFI_PASSWORD" || -z "$WIFI_COUNTRY" ]]; then
        echo -e "${RED}Error: .env is missing required WiFi configuration.${NC}"
        echo "Please ensure WIFI_SSID, WIFI_PASSWORD, and WIFI_COUNTRY are set."
        exit 1
    fi
    
    # Set defaults for optional variables
    HOSTNAME=${HOSTNAME:-ovbuddy}
    USERNAME=${USERNAME:-pi}
    USER_PASSWORD=${USER_PASSWORD:-raspberry}
    
    # Default to automated CLI when using .env (unless overridden)
    SETUP_METHOD="${METHOD_ARG:-1}"
    
    echo -e "${BLUE}Configuration from .env:${NC}"
    echo "  WiFi SSID: $WIFI_SSID"
    echo "  WiFi Password: [hidden]"
    echo "  WiFi Country: $WIFI_COUNTRY"
    echo "  Hostname: $HOSTNAME"
    echo "  Username: $USERNAME"
    echo "  User Password: [hidden]"
    echo ""
    
    if [ "$ASSUME_YES" = true ]; then
        echo -e "${YELLOW}--yes set; skipping interactive confirmation.${NC}"
        echo ""
    else
        read -p "Continue with these settings? (y/N) " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Aborted."
            exit 1
        fi
        echo ""
    fi
else
    # Prompt for setup method
    echo -e "${BLUE}Choose setup method:${NC}"
    echo "  1. Automated CLI (downloads and writes image automatically)"
    echo "  2. Manual GUI (opens Raspberry Pi Imager with instructions)"
    echo ""
    if [[ -n "$METHOD_ARG" ]]; then
        SETUP_METHOD="$METHOD_ARG"
        echo -e "${YELLOW}Using --method ${SETUP_METHOD}${NC}"
    else
        read -p "Enter choice (1 or 2): " SETUP_METHOD
    fi
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

# Only show confirmation if not already shown for .env
if [[ ! -f "$ENV_FILE" ]]; then
    echo -e "${BLUE}Configuration Summary:${NC}"
    echo "  Hostname: $HOSTNAME"
    echo "  Username: $USERNAME"
    echo "  User Password: [hidden]"
    echo "  WiFi SSID: $WIFI_SSID"
    echo "  WiFi Password: [hidden]"
    echo "  WiFi Country: $WIFI_COUNTRY"
    echo ""
    
    if [ "$ASSUME_YES" = true ]; then
        echo -e "${YELLOW}--yes set; skipping interactive confirmation.${NC}"
        echo ""
    else
        read -p "Continue with these settings? (y/N) " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Aborted."
            exit 1
        fi
        echo ""
    fi
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
    
    DISK_ID=""
    if [[ -n "$DISK_ID_ARG" ]]; then
        DISK_ID="$DISK_ID_ARG"
        echo -e "${YELLOW}Using --disk ${DISK_ID}${NC}"
    else
        read -p "Enter the disk identifier (e.g., disk2): " DISK_ID
    fi
    
    if [[ ! "$DISK_ID" =~ ^disk[0-9]+$ ]]; then
        echo -e "${RED}Error: Invalid disk identifier. Must be in format 'diskN'.${NC}"
        exit 1
    fi
    
    # Use /dev/diskN for diskutil operations, but prefer /dev/rdiskN (raw device)
    # for dd writes on macOS — it's *much* faster.
    DISK_PATH="/dev/$DISK_ID"
    RAW_DISK_PATH="/dev/r$DISK_ID"
    WRITE_DISK_PATH="$DISK_PATH"
    if [[ -e "$RAW_DISK_PATH" ]]; then
        WRITE_DISK_PATH="$RAW_DISK_PATH"
    fi
    
    # Confirm disk selection
    echo ""
    echo -e "${RED}WARNING: This will erase ALL data on $DISK_ID!${NC}"
    diskutil info "$DISK_ID" | grep -E "Device Node|Media Name|Total Size"
    echo ""
    if [ "$ASSUME_YES" = true ]; then
        if [[ -z "$DISK_ID_ARG" ]]; then
            echo -e "${RED}Error: --yes requires --disk <diskN> for safety.${NC}"
            exit 1
        fi
        echo -e "${YELLOW}--yes set; proceeding without interactive confirmation.${NC}"
    else
        read -p "Are you ABSOLUTELY sure you want to continue? Type 'YES' to proceed: " CONFIRM
        
        if [[ "$CONFIRM" != "YES" ]]; then
            echo "Aborted."
            exit 1
        fi
    fi
    
    # Create temporary directory
    TEMP_DIR=$(mktemp -d)
    
    # Cleanup function
    cleanup() {
        local exit_code=$?
        if [ -d "$TEMP_DIR" ]; then
            echo ""
            echo -e "${YELLOW}Cleaning up temporary files...${NC}"
            rm -rf "$TEMP_DIR"
        fi
        if [ $exit_code -ne 0 ]; then
            echo -e "${RED}Script failed with exit code $exit_code${NC}"
        fi
    }
    
    # Set trap for cleanup on exit, interrupt, or error
    trap cleanup EXIT INT TERM
    
    # Determine image URL and SHA256 based on selections
    # Note: SHA256 checksums need to be updated when new images are released
    # For now, we'll use the latest images and note that checksums may need updating
    IMAGE_FILE="$TEMP_DIR/raspios.img.xz"
    
    # Build image URL based on variant and architecture
    if [[ "$OS_VARIANT" == "lite" ]]; then
        if [[ "$ARCH" == "armhf" ]]; then
            # 32-bit Lite
            IMAGE_URL="https://downloads.raspberrypi.com/raspios_oldstable_lite_armhf_latest"
            IMAGE_SHA256="2a6ff6474218e5e83b6448771e902a4e5e06a86b9604b3b02f8d69ccc5bfb47b"
            OS_DESC="Lite (32-bit)"
        else
            # 64-bit Lite
            IMAGE_URL="https://downloads.raspberrypi.com/raspios_oldstable_lite_arm64_latest"
            # Note: Update SHA256 when you verify the download
            IMAGE_SHA256=""  # Will skip verification if empty
            OS_DESC="Lite (64-bit)"
        fi
    else
        # Full OS
        if [[ "$ARCH" == "armhf" ]]; then
            # 32-bit Full
            IMAGE_URL="https://downloads.raspberrypi.com/raspios_oldstable_armhf_latest"
            # Note: Update SHA256 when you verify the download
            IMAGE_SHA256=""  # Will skip verification if empty
            OS_DESC="Full (32-bit)"
        else
            # 64-bit Full
            IMAGE_URL="https://downloads.raspberrypi.com/raspios_oldstable_arm64_latest"
            # Note: Update SHA256 when you verify the download
            IMAGE_SHA256=""  # Will skip verification if empty
            OS_DESC="Full (64-bit)"
        fi
    fi
    
    echo ""
    echo -e "${YELLOW}Downloading Raspberry Pi OS ${OS_DESC}...${NC}"
    echo "Release: Debian Bookworm"
    echo "Compatible with: Raspberry Pi $([ "$PI_MODEL" == "zero" ] && echo "Zero W" || echo "4")"
    echo "This may take several minutes depending on your connection."
    echo ""
    
    if ! curl -L -o "$IMAGE_FILE" --progress-bar "$IMAGE_URL"; then
        echo -e "${RED}Error: Failed to download image.${NC}"
        exit 1
    fi
    
    echo ""
    echo -e "${GREEN}✓ Download complete${NC}"
    echo ""
    
    # Get uncompressed size for progress bar (not for validation - hash check is sufficient)
    # xz -l outputs format like: "4,567.8 MiB" - fields 5 and 6 contain number and unit
    UNCOMPRESSED_BYTES=""
    if command -v xz &> /dev/null; then
        XZ_INFO=$(xz -l "$IMAGE_FILE" 2>/dev/null | tail -1)
        if [[ -n "$XZ_INFO" ]]; then
            # Extract number (field 5) and unit (field 6), remove commas
            UNCOMPRESSED_NUM=$(echo "$XZ_INFO" | awk '{print $5}' | sed 's/,//g')
            UNCOMPRESSED_UNIT=$(echo "$XZ_INFO" | awk '{print $6}')
            if [[ -n "$UNCOMPRESSED_NUM" && -n "$UNCOMPRESSED_UNIT" ]]; then
                # Convert to bytes using awk (works without bc)
                case "$UNCOMPRESSED_UNIT" in
                    *[Kk][Ii]*[Bb]*) 
                        UNCOMPRESSED_BYTES=$(awk "BEGIN {printf \"%.0f\", $UNCOMPRESSED_NUM * 1024}")
                        ;;
                    *[Mm][Ii]*[Bb]*) 
                        UNCOMPRESSED_BYTES=$(awk "BEGIN {printf \"%.0f\", $UNCOMPRESSED_NUM * 1024 * 1024}")
                        ;;
                    *[Gg][Ii]*[Bb]*) 
                        UNCOMPRESSED_BYTES=$(awk "BEGIN {printf \"%.0f\", $UNCOMPRESSED_NUM * 1024 * 1024 * 1024}")
                        ;;
                    *[Tt][Ii]*[Bb]*) 
                        UNCOMPRESSED_BYTES=$(awk "BEGIN {printf \"%.0f\", $UNCOMPRESSED_NUM * 1024 * 1024 * 1024 * 1024}")
                        ;;
                    *) 
                        UNCOMPRESSED_BYTES=$(awk "BEGIN {printf \"%.0f\", $UNCOMPRESSED_NUM}")
                        ;;
                esac
            fi
        fi
    fi
    
    # Verify SHA256 checksum (if available)
    if [[ -n "$IMAGE_SHA256" ]]; then
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
    else
        echo -e "${YELLOW}⚠ SHA256 checksum not configured for this image variant.${NC}"
        echo -e "${YELLOW}  Skipping integrity check. Please verify the download manually if needed.${NC}"
        echo ""
    fi
    
    # Unmount the disk (but don't eject it)
    echo -e "${YELLOW}Unmounting disk...${NC}"
    diskutil unmountDisk "$DISK_PATH" || true
    
    # Write the image
    echo ""
    echo -e "${YELLOW}Writing image to SD card...${NC}"
    echo "This will take several minutes. Please be patient."
    if [[ "$WRITE_DISK_PATH" == "$RAW_DISK_PATH" ]]; then
        echo -e "${BLUE}Using raw device for speed: $WRITE_DISK_PATH${NC}"
    else
        echo -e "${YELLOW}Using buffered device (slower): $WRITE_DISK_PATH${NC}"
        echo -e "${YELLOW}Tip: if /dev/rdisk* exists on your system, it will be used automatically for faster writes.${NC}"
    fi
    echo ""
    
    # Check if pv (pipe viewer) is available for progress bar
    USE_PV=false
    if command -v pv &> /dev/null && [[ -n "$UNCOMPRESSED_BYTES" && "$UNCOMPRESSED_BYTES" -gt 0 ]]; then
        USE_PV=true
        echo -e "${BLUE}Using progress bar...${NC}"
    fi
    
    # Calculate expected max bytes (uncompressed size + 10% tolerance)
    if [[ -n "$UNCOMPRESSED_BYTES" && "$UNCOMPRESSED_BYTES" -gt 0 ]]; then
        MAX_EXPECTED_BYTES=$((UNCOMPRESSED_BYTES + UNCOMPRESSED_BYTES / 10))
        # Safety limit: abort if writing more than 10GB (way too much)
        ABSOLUTE_MAX_BYTES=10000000000
    else
        # Fallback: expect max 6GB if we couldn't determine size
        MAX_EXPECTED_BYTES=6000000000
        ABSOLUTE_MAX_BYTES=10000000000
    fi
    
    # Use xzcat (single-threaded) - often faster than multi-threaded for streaming
    # Performance notes on macOS:
    # - Writing to /dev/rdiskN is critical (raw device)
    # - Buffering matters: without buffering, pipes can cause many small writes and be extremely slow
    # We therefore use pv's buffer (-B) and a larger dd block size.
    # Capture dd output to check if write was successful (even if exit code is non-zero)
    # "end of device" warning is normal when image is slightly larger than card
    if [ "$USE_PV" = true ]; then
        # Use a temporary file to capture dd output while letting pv show progress
        TEMP_DD_OUTPUT=$(mktemp)
        sudo sh -c "xzcat '$IMAGE_FILE' | pv -B 16m -s $UNCOMPRESSED_BYTES -p -t -e -b | dd of='$WRITE_DISK_PATH' bs=16m 2>$TEMP_DD_OUTPUT" || true
        DD_OUTPUT=$(cat "$TEMP_DD_OUTPUT")
        rm -f "$TEMP_DD_OUTPUT"
    else
        DD_OUTPUT=$(sudo sh -c "xzcat '$IMAGE_FILE' | dd of='$WRITE_DISK_PATH' bs=16m 2>&1" || true)
    fi
    
    # Check if dd actually wrote data successfully
    # Look for "bytes transferred" in the output (indicates successful write)
    if echo "$DD_OUTPUT" | grep -q "bytes transferred"; then
        # Extract bytes written from dd output (format: "N bytes transferred in X secs")
        BYTES_WRITTEN=$(echo "$DD_OUTPUT" | grep "bytes transferred" | sed -E 's/([0-9]+) bytes transferred.*/\1/' | tail -1)
        
        if [[ -z "$BYTES_WRITTEN" ]]; then
            echo -e "${RED}Error: Could not determine bytes written from dd output${NC}"
            echo "$DD_OUTPUT"
            exit 1
        fi
        
        # Safety check: abort if writing way too much (indicates corruption or wrong file)
        if [[ "$BYTES_WRITTEN" -gt "$ABSOLUTE_MAX_BYTES" ]]; then
            echo -e "${RED}Error: Write aborted - too much data written (${BYTES_WRITTEN} bytes = ~$((BYTES_WRITTEN / 1000000000))GB)${NC}"
            echo -e "${RED}Expected maximum: ~$((MAX_EXPECTED_BYTES / 1000000000))GB${NC}"
            echo ""
            echo "This suggests the image file may be corrupted or the wrong file was downloaded."
            echo "Please check the downloaded file and try again."
            echo ""
            echo "$DD_OUTPUT"
            exit 1
        fi
        
        # Check if reasonable amount was written
        if [[ "$BYTES_WRITTEN" -lt 1000000 ]]; then
            echo -e "${RED}Error: Write appears to have failed (insufficient bytes written: ${BYTES_WRITTEN})${NC}"
            echo "$DD_OUTPUT"
            exit 1
        fi
        
        # Warn if more than expected (but less than absolute max)
        if [[ -n "$MAX_EXPECTED_BYTES" && "$BYTES_WRITTEN" -gt "$MAX_EXPECTED_BYTES" ]]; then
            echo -e "${YELLOW}Warning: More bytes written than expected (${BYTES_WRITTEN} vs expected ~${UNCOMPRESSED_BYTES})${NC}"
            echo -e "${YELLOW}This may indicate an issue, but continuing...${NC}"
        fi
        
        echo ""
        echo -e "${GREEN}✓ Image written successfully (${BYTES_WRITTEN} bytes = ~$((BYTES_WRITTEN / 1000000000))GB)${NC}"
        if echo "$DD_OUTPUT" | grep -q "end of device"; then
            echo -e "${YELLOW}  Note: 'end of device' warning is normal when image is slightly larger than SD card${NC}"
        fi
    else
        echo -e "${RED}Error: Failed to write image.${NC}"
        echo "$DD_OUTPUT"
        exit 1
    fi
    
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

    # Extra safety: enable SSH the legacy way too (works even if firstrun doesn't run)
    # This is compatible with many Raspberry Pi OS images.
    echo -e "${YELLOW}Enabling SSH on first boot (boot partition flag)...${NC}"
    touch "$BOOT_VOLUME/ssh" || true
    echo -e "${GREEN}✓ SSH flag written${NC}"
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

    # Extra safety: write wpa_supplicant.conf onto boot partition as well.
    # Many images will import this on first boot; it helps if firstrun doesn't execute.
    echo -e "${YELLOW}Writing WiFi config to boot partition (fallback)...${NC}"
    cat > "$BOOT_VOLUME/wpa_supplicant.conf" << WPA_BOOT_EOF
country=$WIFI_COUNTRY
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1

network={
    ssid="$WIFI_SSID"
    psk=$WIFI_PSK_HASH
}
WPA_BOOT_EOF
    chmod 600 "$BOOT_VOLUME/wpa_supplicant.conf" 2>/dev/null || true
    echo -e "${GREEN}✓ WiFi fallback written${NC}"
    echo ""

    # Stage e-ink driver + ready-screen script onto the boot partition so the Pi can
    # show a "Ready to deploy" message after first-boot provisioning completes.
    echo -e "${YELLOW}Staging e-ink driver + ready screen onto boot partition...${NC}"
    OVBUDDY_EINK_DIR="$BOOT_VOLUME/ovbuddy_eink"
    mkdir -p "$OVBUDDY_EINK_DIR"
    
    DIST_DIR="$PROJECT_ROOT/dist"
    if [ -f "$DIST_DIR/epd2in13_V4.py" ] && [ -f "$DIST_DIR/epdconfig.py" ] && [ -f "$DIST_DIR/ovbuddy_eink_ready.py" ]; then
        cp "$DIST_DIR/epd2in13_V4.py" "$OVBUDDY_EINK_DIR/"
        cp "$DIST_DIR/epdconfig.py" "$OVBUDDY_EINK_DIR/"
        cp "$DIST_DIR/ovbuddy_eink_ready.py" "$OVBUDDY_EINK_DIR/"
        chmod 755 "$OVBUDDY_EINK_DIR/ovbuddy_eink_ready.py" 2>/dev/null || true
        echo -e "${GREEN}✓ e-ink files staged at: $OVBUDDY_EINK_DIR${NC}"
    else
        echo -e "${YELLOW}⚠ e-ink driver files not found in dist/. Skipping ready-screen staging.${NC}"
        echo -e "${YELLOW}  Expected: dist/epd2in13_V4.py, dist/epdconfig.py, dist/ovbuddy_eink_ready.py${NC}"
    fi
    echo ""
    
    # Generate password hash - try openssl first, then Python as fallback
    echo -e "${YELLOW}Generating password hash...${NC}"
    
    PASSWORD_HASH=""
    
    # Method 1: Prefer an OpenSSL that supports SHA-512 crypt (-6).
    # NOTE: macOS system OpenSSL is typically LibreSSL and does NOT support -6.
    OPENSSL_BIN=""
    find_openssl_sha512() {
        local candidates=()
        # Homebrew (preferred on macOS)
        if command -v brew >/dev/null 2>&1; then
            local prefix=""
            prefix=$(brew --prefix openssl@3 2>/dev/null || true)
            if [[ -n "$prefix" && -x "$prefix/bin/openssl" ]]; then candidates+=("$prefix/bin/openssl"); fi
            prefix=$(brew --prefix openssl@1.1 2>/dev/null || true)
            if [[ -n "$prefix" && -x "$prefix/bin/openssl" ]]; then candidates+=("$prefix/bin/openssl"); fi
            prefix=$(brew --prefix openssl 2>/dev/null || true)
            if [[ -n "$prefix" && -x "$prefix/bin/openssl" ]]; then candidates+=("$prefix/bin/openssl"); fi
        fi
        # Common locations
        candidates+=("/opt/homebrew/opt/openssl@3/bin/openssl" "/usr/local/opt/openssl@3/bin/openssl" "/opt/homebrew/bin/openssl" "/usr/local/bin/openssl")
        # Whatever is on PATH last (may be LibreSSL)
        if command -v openssl >/dev/null 2>&1; then candidates+=("$(command -v openssl)"); fi
        local bin=""
        for bin in "${candidates[@]}"; do
            [[ -n "$bin" && -x "$bin" ]] || continue
            if "$bin" passwd -6 "test" >/dev/null 2>&1; then
                echo "$bin"
                return 0
            fi
        done
        return 1
    }
    
    if OPENSSL_BIN="$(find_openssl_sha512 2>/dev/null)"; then
        # Guard command substitution so failure doesn't abort the script.
        if PASSWORD_HASH=$("$OPENSSL_BIN" passwd -6 -stdin 2>/dev/null <<<"$USER_PASSWORD"); then
            echo -e "${GREEN}✓ Password hash generated (via OpenSSL: $OPENSSL_BIN)${NC}"
        else
            PASSWORD_HASH=""
        fi
    fi
    
    # Method 2: Fallback to Python crypt module
    if [ -z "$PASSWORD_HASH" ]; then
        if command -v python3 &> /dev/null; then
            # Don't pass password via stdin here: python is already reading its program from stdin.
            # Use an env var instead to keep it simple and reliable.
            if PASSWORD_HASH=$(USER_PASSWORD="$USER_PASSWORD" python3 - << 'PYEOF' 2>/dev/null
import os
import sys
try:
    import crypt
    password = os.environ.get("USER_PASSWORD", "")
    if not password:
        sys.exit(1)
    hash_val = crypt.crypt(password, crypt.mksalt(crypt.METHOD_SHA512))
    if not hash_val:
        sys.exit(1)
    print(hash_val)
except (ImportError, AttributeError):
    sys.exit(1)
PYEOF
); then
                echo -e "${GREEN}✓ Password hash generated (via Python)${NC}"
            else
                PASSWORD_HASH=""
            fi
        fi
    fi
    
    # Validate hash (must be SHA-512 crypt: $6$salt$hash)
    # Avoid regex here: bash escaping differs across environments and it's easy to get wrong.
    if [[ -n "$PASSWORD_HASH" ]]; then
        if [[ "$PASSWORD_HASH" == \$6\$* ]]; then
            # Parameter expansion patterns are globs, not regex.
            # Use \$ to represent a literal '$' in the glob patterns.
            REST="${PASSWORD_HASH#\$6\$}"
            SALT="${REST%%\$*}"
            HASH="${REST#*\$}"
            if [[ -z "$SALT" || "$REST" != *\$* || -z "$HASH" ]]; then
                echo -e "${YELLOW}⚠ Generated password hash is not in expected SHA-512 crypt format. Discarding.${NC}"
                PASSWORD_HASH=""
            fi
        else
            echo -e "${YELLOW}⚠ Generated password hash is not in expected SHA-512 crypt format. Discarding.${NC}"
            PASSWORD_HASH=""
        fi
    fi
    
    if [ -z "$PASSWORD_HASH" ]; then
        echo -e "${RED}Error: Failed to generate a valid SHA-512 password hash for userconf.txt${NC}"
        echo ""
        echo "On macOS, the system OpenSSL is usually LibreSSL and can't generate '-6' hashes."
        echo "Fix:"
        echo "  brew install openssl@3"
        echo ""
        echo "Then re-run this script to recreate the SD card."
        echo ""
        echo "Alternative:"
        echo "  Use setup method 2 (Raspberry Pi Imager) which sets the password for you."
        echo ""
        exit 1
    fi

    # Extra safety: write userconf.txt onto the boot partition.
    # Raspberry Pi OS will consume this on first boot to set username/password,
    # even if our firstrun.sh mechanism doesn't execute for any reason.
    echo -e "${YELLOW}Writing user password config to boot partition (userconf.txt fallback)...${NC}"
    printf '%s:%s\n' "$USERNAME" "$PASSWORD_HASH" > "$BOOT_VOLUME/userconf.txt"
    chmod 600 "$BOOT_VOLUME/userconf.txt" 2>/dev/null || true
    echo -e "${GREEN}✓ userconf.txt written${NC}"
    echo ""
    
    # Create firstrun.sh script (matches Raspberry Pi Imager approach)
    echo -e "${YELLOW}Creating firstrun.sh script...${NC}"
    cat > "$BOOT_VOLUME/firstrun.sh" << 'FIRSTRUN_EOF'
#!/bin/sh

set +e

# Bookworm commonly mounts the FAT firmware partition at /boot/firmware (not /boot).
# Detect the correct mountpoint so our cleanup and cmdline edits work reliably.
BOOT_MNT="/boot"
if [ -d "/boot/firmware" ]; then
  BOOT_MNT="/boot/firmware"
fi

# Enable SPI for the e-ink display (safe to do even if already enabled)
if [ -f "$BOOT_MNT/config.txt" ]; then
  if ! grep -q '^dtparam=spi=on' "$BOOT_MNT/config.txt" 2>/dev/null; then
    echo 'dtparam=spi=on' >> "$BOOT_MNT/config.txt"
  fi
fi

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
	key_mgmt=WPA-PSK
	psk=WIFI_PSK_HASH_PLACEHOLDER
}
WPAEOF
   chmod 600 /etc/wpa_supplicant/wpa_supplicant.conf
   rfkill unblock wifi
   for filename in /var/lib/systemd/rfkill/*:wlan ; do
       echo 0 > $filename
   done
fi

# Create a second-boot service to install Avahi + e-ink deps after network is fully online,
# then show "Ready to deploy" on the e-ink display.
# This is the Bookworm-safe pattern - don't install packages in firstrun.sh
cat > /etc/systemd/system/ovbuddy-postboot.service << 'POSTBOOTEOF'
[Unit]
Description=OVBuddy Post-Boot Setup (Install Avahi + e-ink deps)
After=network-online.target
Wants=network-online.target
ConditionPathExists=!/etc/ovbuddy-postboot-done

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 10
ExecStart=/usr/bin/apt-get update -qq
ExecStart=/usr/bin/apt-get install -y git avahi-daemon python3-pil python3-numpy python3-gpiozero python3-spidev python3-rpi.gpio
ExecStart=/bin/systemctl enable avahi-daemon
ExecStart=/bin/systemctl start avahi-daemon
# Best-effort: show an on-screen "ready" signal; never block boot on display errors.
ExecStart=/bin/bash -lc 'BOOT_MNT=/boot; [ -d /boot/firmware ] && BOOT_MNT=/boot/firmware; if [ -f "$BOOT_MNT/ovbuddy_eink/ovbuddy_eink_ready.py" ]; then PYTHONPATH="$BOOT_MNT/ovbuddy_eink" /usr/bin/python3 "$BOOT_MNT/ovbuddy_eink/ovbuddy_eink_ready.py" || true; fi'
ExecStart=/bin/touch /etc/ovbuddy-postboot-done
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
POSTBOOTEOF

# Enable the service to run on next boot (after WiFi is up)
systemctl enable ovbuddy-postboot.service

# Clean up firstrun.sh and reboot
rm -f "$BOOT_MNT/firstrun.sh"
sed -i 's| systemd.run.*||g' "$BOOT_MNT/cmdline.txt"

# Exit successfully - systemd.run_success_action=reboot will trigger reboot
exit 0
FIRSTRUN_EOF
    
    # Replace placeholders in firstrun.sh
    sed -i '' "s/HOSTNAME_PLACEHOLDER/$HOSTNAME/g" "$BOOT_VOLUME/firstrun.sh"
    sed -i '' "s/USERNAME_PLACEHOLDER/$USERNAME/g" "$BOOT_VOLUME/firstrun.sh"
    sed -i '' "s|PASSWORD_HASH_PLACEHOLDER|$PASSWORD_HASH|g" "$BOOT_VOLUME/firstrun.sh"
    sed -i '' "s/WIFI_SSID_PLACEHOLDER/$WIFI_SSID/g" "$BOOT_VOLUME/firstrun.sh"
    sed -i '' "s|WIFI_PSK_HASH_PLACEHOLDER|$WIFI_PSK_HASH|g" "$BOOT_VOLUME/firstrun.sh"
    sed -i '' "s/WIFI_COUNTRY_PLACEHOLDER/$WIFI_COUNTRY/g" "$BOOT_VOLUME/firstrun.sh"
    
    # Make firstrun.sh executable and verify
    if ! chmod +x "$BOOT_VOLUME/firstrun.sh"; then
        echo -e "${RED}Error: Failed to make firstrun.sh executable${NC}"
        exit 1
    fi
    
    # Verify the file exists and is executable
    if [ ! -x "$BOOT_VOLUME/firstrun.sh" ]; then
        echo -e "${RED}Error: firstrun.sh is not executable${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ firstrun.sh created and verified${NC}"
    
    # Modify cmdline.txt to add systemd.run parameter.
    # IMPORTANT: Use /boot/firstrun.sh for systemd.run.
    # /boot is the most compatible path across Pi OS variants/boot stages; on Bookworm,
    # /boot is typically a compatibility mount/symlink to /boot/firmware.
    echo -e "${YELLOW}Configuring boot parameters...${NC}"
    RUN_PATH="/boot/firstrun.sh"
    if ! grep -q "systemd.run=" "$BOOT_VOLUME/cmdline.txt"; then
        # Add systemd.run parameters to cmdline.txt
        CMDLINE=$(cat "$BOOT_VOLUME/cmdline.txt")
        echo "$CMDLINE systemd.run=$RUN_PATH systemd.run_success_action=reboot systemd.unit=kernel-command-line.target" > "$BOOT_VOLUME/cmdline.txt"
        echo -e "${GREEN}✓ Boot parameters configured${NC}"
    else
        echo -e "${GREEN}✓ Boot parameters already configured${NC}"
    fi
    
    # Sync and unmount
    echo ""
    echo -e "${YELLOW}Syncing and ejecting SD card...${NC}"
    sync
    
    # Spotlight (mds) can briefly hold the boot volume open right after writes, causing
    # "Unmount was dissented" even though the card is actually ready. Retry and fall back
    # to a warning instead of failing the whole run.
    EJECT_OK=false
    for attempt in 1 2 3 4 5; do
        if diskutil eject "$DISK_PATH" > /dev/null 2>&1; then
            EJECT_OK=true
            break
        fi
        sleep 1
    done
    
    if [ "$EJECT_OK" != true ]; then
        echo -e "${YELLOW}⚠ Could not eject $DISK_ID (macOS is holding the volume open).${NC}"
        echo -e "${YELLOW}  This is usually safe to ignore because data has been synced, but please eject manually:${NC}"
        echo "    diskutil unmountDisk force \"$DISK_PATH\" || true"
        echo "    diskutil eject \"$DISK_PATH\""
        echo ""
    fi
    
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  SD CARD SETUP COMPLETE!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Your SD card is ready! Next steps:"
    echo ""
    echo "1. Insert the SD card into your Raspberry Pi $([ "$PI_MODEL" == "zero" ] && echo "Zero W" || echo "4")"
    echo "2. Power on the Pi"
    echo ""
    echo "   First boot (2-3 minutes):"
    echo "   - Set hostname to '${HOSTNAME}'"
    echo "   - Configure WiFi (WPA2-compatible)"
    echo "   - Enable SSH"
    echo "   - Set up user '${USERNAME}'"
    echo "   - Create post-boot service"
    echo "   - Reboot automatically"
    echo ""
    echo "   Second boot (2-3 minutes):"
    echo "   - Connect to WiFi"
    echo "   - Install Avahi (mDNS for .local hostname)"
    echo "   - Install e-ink prerequisites + enable SPI"
    echo "   - Show 'Ready to deploy' on the e-ink display"
    echo ""
    echo "   Total time: ~5-6 minutes from first power-on"
    echo ""
    echo "3. After 6 minutes, test the connection:"
    echo "   ping ${HOSTNAME}.local"
    echo "   ssh ${USERNAME}@${HOSTNAME}.local"
    echo ""
    echo "   If .local doesn't work, find the IP:"
    echo "   cd scripts && ./find-pi.sh"
    echo ""
    echo "4. Update the .env file in the OVBuddy project:"
    echo "   PI_HOST=${HOSTNAME}.local"
    echo "   PI_USER=${USERNAME}"
    echo "   PI_PASSWORD=[your password from .env]"
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
    if [[ "$PI_MODEL" == "zero" ]]; then
        echo "   → Raspberry Pi Zero W"
    else
        echo "   → Raspberry Pi 4"
    fi
    echo ""
    echo "3. Click 'CHOOSE OS' and select:"
    echo "   → Raspberry Pi OS (other)"
    if [[ "$OS_VARIANT" == "lite" ]]; then
        if [[ "$ARCH" == "armhf" ]]; then
            echo "   → Raspberry Pi OS Lite (32-bit)"
        else
            echo "   → Raspberry Pi OS Lite (64-bit)"
        fi
    else
        if [[ "$ARCH" == "armhf" ]]; then
            echo "   → Raspberry Pi OS (32-bit) - with desktop"
        else
            echo "   → Raspberry Pi OS (64-bit) - with desktop"
        fi
    fi
    echo "   → Latest version (Bookworm)"
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
