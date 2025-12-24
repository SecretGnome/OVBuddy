#!/bin/bash

# Script to retrieve compiled zeroconf package from Raspberry Pi
# This allows you to reuse the compiled package on another Pi without recompiling
# Usage: ./scripts/retrieve-zeroconf.sh

# Change to project root directory (parent of scripts/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if .env file exists
if [ ! -f .env ]; then
    echo -e "${RED}Error: .env file not found!${NC}"
    echo "Please create a .env file with the following variables:"
    echo "  PI_HOST=raspberrypi.local"
    echo "  PI_USER=pi"
    echo "  PI_PASSWORD=your_password"
    exit 1
fi

# Load environment variables from .env file
set -a
source .env
set +a

# Validate required variables
if [ -z "$PI_HOST" ] || [ -z "$PI_USER" ] || [ -z "$PI_PASSWORD" ]; then
    echo -e "${RED}Error: PI_HOST, PI_USER, and PI_PASSWORD must be set in .env file${NC}"
    exit 1
fi

# Check if sshpass is installed
if ! command -v sshpass &> /dev/null; then
    echo -e "${RED}Error: sshpass is required for password authentication${NC}"
    echo "Install it with:"
    echo "  macOS: brew install hudochenkov/sshpass/sshpass"
    echo "  Linux: apt-get install sshpass"
    exit 1
fi

SSH_OPTS="-o StrictHostKeyChecking=no"
SCP_OPTS="-o StrictHostKeyChecking=no"

# Get IP for SSH connection
PI_SSH_HOST="$PI_HOST"
if [[ "$PI_HOST" == *.local ]]; then
    HOSTNAME_SHORT=$(echo "$PI_HOST" | sed 's/\.local$//')
    PI_IP=$(arp -a 2>/dev/null | grep -i "$HOSTNAME_SHORT" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
    if [ -z "$PI_IP" ]; then
        PI_IP=$(ping -c 1 -W 1 "$PI_HOST" 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
    fi
    if [ -n "$PI_IP" ] && [[ "$PI_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        PI_SSH_HOST="$PI_IP"
    fi
fi

echo -e "${YELLOW}Retrieving compiled zeroconf from ${PI_USER}@${PI_SSH_HOST}${NC}"
echo ""

# Create local directory for retrieved packages
LOCAL_PACKAGES_DIR="retrieved-packages"
mkdir -p "$LOCAL_PACKAGES_DIR"

# Find Python version and site-packages location on Pi
echo -e "${BLUE}Step 1: Detecting Python installation on Pi...${NC}"
PYTHON_VERSION=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "python3 --version | grep -oE '[0-9]+\.[0-9]+' | head -1")
echo "  Python version: $PYTHON_VERSION"

# Find where zeroconf is installed
echo ""
echo -e "${BLUE}Step 2: Locating zeroconf installation...${NC}"
ZEROCONF_LOCATION=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
    python3 -c 'import zeroconf; import os; print(os.path.dirname(zeroconf.__file__))' 2>/dev/null || echo ''
")

if [ -z "$ZEROCONF_LOCATION" ]; then
    echo -e "${RED}Error: zeroconf is not installed on the Pi${NC}"
    echo "Please install it first with: pip3 install --break-system-packages zeroconf"
    exit 1
fi

echo "  Found zeroconf at: $ZEROCONF_LOCATION"

# Find the parent site-packages directory
SITE_PACKAGES_DIR=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
    python3 -c 'import site; print(site.getsitepackages()[0] if site.getsitepackages() else \"\")' 2>/dev/null || \
    python3 -c 'import sys; print([p for p in sys.path if \"site-packages\" in p][0] if [p for p in sys.path if \"site-packages\" in p] else \"\")' 2>/dev/null || \
    echo ''
")

# Also check user site-packages
USER_SITE_PACKAGES=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
    python3 -c 'import site; print(site.getusersitepackages())' 2>/dev/null || echo ''
")

echo "  System site-packages: ${SITE_PACKAGES_DIR:-not found}"
echo "  User site-packages: ${USER_SITE_PACKAGES:-not found}"

# Determine which directory contains zeroconf
if [[ "$ZEROCONF_LOCATION" == "$USER_SITE_PACKAGES"* ]]; then
    PACKAGE_BASE_DIR="$USER_SITE_PACKAGES"
    INSTALL_TYPE="user"
elif [[ "$ZEROCONF_LOCATION" == "$SITE_PACKAGES_DIR"* ]]; then
    PACKAGE_BASE_DIR="$SITE_PACKAGES_DIR"
    INSTALL_TYPE="system"
else
    # Fallback: use the parent directory of zeroconf
    PACKAGE_BASE_DIR=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "dirname '$ZEROCONF_LOCATION'")
    INSTALL_TYPE="unknown"
fi

echo "  Package base directory: $PACKAGE_BASE_DIR"
echo "  Install type: $INSTALL_TYPE"

# Get zeroconf version
ZEROCONF_VERSION=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
    python3 -c 'import zeroconf; print(zeroconf.__version__)' 2>/dev/null || echo 'unknown'
")
echo "  zeroconf version: $ZEROCONF_VERSION"

# Check for compiled extensions (.so files)
echo ""
echo -e "${BLUE}Step 3: Checking for compiled extensions...${NC}"
COMPILED_FILES=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
    find '$ZEROCONF_LOCATION' -name '*.so' -o -name '*.so.*' 2>/dev/null | head -10
")
if [ -n "$COMPILED_FILES" ]; then
    echo "  Found compiled files:"
    echo "$COMPILED_FILES" | sed 's/^/    /'
else
    echo "  No compiled .so files found (may be pure Python)"
fi

# Create archive name with version and architecture
ARCH=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "uname -m")
ARCHIVE_NAME="zeroconf-${ZEROCONF_VERSION}-python${PYTHON_VERSION}-${ARCH}.tar.gz"
ARCHIVE_PATH="/tmp/${ARCHIVE_NAME}"

echo ""
echo -e "${BLUE}Step 4: Creating archive on Pi...${NC}"
echo "  Archive: $ARCHIVE_NAME"

# Create archive on Pi
sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
    cd '$PACKAGE_BASE_DIR'
    # Get the zeroconf directory name
    ZEROCONF_DIR=\$(basename '$ZEROCONF_LOCATION')
    # Also include zeroconf-*.dist-info if it exists
    tar czf '$ARCHIVE_PATH' \\
        --exclude='__pycache__' \\
        --exclude='*.pyc' \\
        --exclude='*.pyo' \\
        \"\$ZEROCONF_DIR\" \\
        zeroconf-*.dist-info 2>/dev/null || \\
    tar czf '$ARCHIVE_PATH' \\
        --exclude='__pycache__' \\
        --exclude='*.pyc' \\
        --exclude='*.pyo' \\
        \"\$ZEROCONF_DIR\"
    
    if [ -f '$ARCHIVE_PATH' ]; then
        ls -lh '$ARCHIVE_PATH'
        echo 'Archive created successfully'
    else
        echo 'Failed to create archive'
        exit 1
    fi
" || {
    echo -e "${RED}Error: Failed to create archive on Pi${NC}"
    exit 1
}

# Download the archive
echo ""
echo -e "${BLUE}Step 5: Downloading archive...${NC}"
LOCAL_ARCHIVE="${LOCAL_PACKAGES_DIR}/${ARCHIVE_NAME}"
sshpass -p "$PI_PASSWORD" scp $SCP_OPTS "${PI_USER}@${PI_SSH_HOST}:${ARCHIVE_PATH}" "$LOCAL_ARCHIVE" || {
    echo -e "${RED}Error: Failed to download archive${NC}"
    exit 1
}

# Verify download
if [ -f "$LOCAL_ARCHIVE" ]; then
    ARCHIVE_SIZE=$(du -h "$LOCAL_ARCHIVE" | cut -f1)
    echo -e "${GREEN}  ✓ Archive downloaded: $LOCAL_ARCHIVE (${ARCHIVE_SIZE})${NC}"
else
    echo -e "${RED}Error: Archive file not found after download${NC}"
    exit 1
fi

# Clean up remote archive
echo ""
echo -e "${BLUE}Step 6: Cleaning up...${NC}"
sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "rm -f '$ARCHIVE_PATH'" 2>/dev/null || true

# Check for dependencies that might need to be retrieved
echo ""
echo -e "${BLUE}Step 7: Checking for compiled dependencies...${NC}"
DEPENDENCIES=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
    python3 -c 'import zeroconf; import pkg_resources; deps = pkg_resources.get_distribution(\"zeroconf\").requires(); [print(d.name) for d in deps]' 2>/dev/null || echo ''
")

if [ -n "$DEPENDENCIES" ]; then
    echo "  Dependencies: $DEPENDENCIES"
    echo -e "${YELLOW}  Note: You may also want to retrieve these dependencies if they are compiled${NC}"
fi

echo ""
echo -e "${GREEN}✓ zeroconf package retrieved successfully!${NC}"
echo ""
echo "Archive location: $LOCAL_ARCHIVE"
echo ""
echo "To install on another Pi:"
echo "  1. Copy the archive to the new Pi:"
echo "     scp $LOCAL_ARCHIVE ${PI_USER}@new-pi-host:/tmp/"
echo ""
echo "  2. Extract and install on the new Pi:"
echo "     ssh ${PI_USER}@new-pi-host"
echo "     cd /tmp"
echo "     sudo tar -xzf $ARCHIVE_NAME -C \$(python3 -c 'import site; print(site.getsitepackages()[0])')"
echo "     # Or for user installation:"
echo "     tar -xzf $ARCHIVE_NAME -C \$(python3 -c 'import site; print(site.getusersitepackages())')"
echo ""
echo "  3. Or use the deploy script with the archive in retrieved-packages/"
echo ""

