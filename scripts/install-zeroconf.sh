#!/bin/bash

# Script to install pre-compiled zeroconf package on Raspberry Pi
# This uses an archive retrieved from another Pi to avoid recompiling
# Usage: ./scripts/install-zeroconf.sh [archive-name] [--user|--system]
#   If archive-name is not provided, will use the most recent archive in retrieved-packages/
#   --user: Install to user site-packages (default)
#   --system: Install to system site-packages (requires sudo)

# Change to project root directory (parent of scripts/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

set -e  # Exit on error

# Parse command line arguments
INSTALL_PREFERENCE="user"  # Default to user installation
ARCHIVE_ARG=""
for arg in "$@"; do
    case $arg in
        --user)
            INSTALL_PREFERENCE="user"
            ;;
        --system)
            INSTALL_PREFERENCE="system"
            ;;
        *)
            if [ -z "$ARCHIVE_ARG" ]; then
                ARCHIVE_ARG="$arg"
            fi
            ;;
    esac
done

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

# Determine which archive to use
RETRIEVED_PACKAGES_DIR="retrieved-packages"
if [ -n "$ARCHIVE_ARG" ]; then
    # Use specified archive
    if [[ "$ARCHIVE_ARG" == *"/"* ]]; then
        ARCHIVE_PATH="$ARCHIVE_ARG"
    else
        ARCHIVE_PATH="${RETRIEVED_PACKAGES_DIR}/$ARCHIVE_ARG"
    fi
else
    # Use most recent archive in retrieved-packages/
    if [ ! -d "$RETRIEVED_PACKAGES_DIR" ]; then
        echo -e "${RED}Error: $RETRIEVED_PACKAGES_DIR/ directory not found!${NC}"
        echo "Please run ./scripts/retrieve-zeroconf.sh first to retrieve a package, or specify an archive path."
        exit 1
    fi
    
    ARCHIVE_PATH=$(ls -t "${RETRIEVED_PACKAGES_DIR}"/zeroconf-*.tar.gz 2>/dev/null | head -1)
    if [ -z "$ARCHIVE_PATH" ]; then
        echo -e "${RED}Error: No zeroconf archives found in $RETRIEVED_PACKAGES_DIR/${NC}"
        echo "Please run ./scripts/retrieve-zeroconf.sh first to retrieve a package, or specify an archive path."
        exit 1
    fi
fi

# Check if archive exists
if [ ! -f "$ARCHIVE_PATH" ]; then
    echo -e "${RED}Error: Archive not found: $ARCHIVE_PATH${NC}"
    exit 1
fi

ARCHIVE_NAME=$(basename "$ARCHIVE_PATH")
echo -e "${YELLOW}Installing zeroconf from ${ARCHIVE_NAME} to ${PI_USER}@${PI_SSH_HOST}${NC}"
echo ""

# Extract version and architecture info from archive name
if [[ "$ARCHIVE_NAME" =~ zeroconf-([^-]+)-python([^-]+)-(.+)\.tar\.gz ]]; then
    ZEROCONF_VERSION="${BASH_REMATCH[1]}"
    PYTHON_VERSION="${BASH_REMATCH[2]}"
    ARCH="${BASH_REMATCH[3]}"
    echo "  Package version: $ZEROCONF_VERSION"
    echo "  Python version: $PYTHON_VERSION"
    echo "  Architecture: $ARCH"
else
    echo -e "${YELLOW}  Warning: Could not parse version info from archive name${NC}"
    ZEROCONF_VERSION="unknown"
    PYTHON_VERSION="unknown"
    ARCH="unknown"
fi

# Check Python version on target Pi
echo ""
echo -e "${BLUE}Step 1: Checking Python version on target Pi...${NC}"
TARGET_PYTHON_VERSION=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "python3 --version | grep -oE '[0-9]+\.[0-9]+' | head -1")
echo "  Target Python version: $TARGET_PYTHON_VERSION"

if [ "$PYTHON_VERSION" != "unknown" ] && [ "$PYTHON_VERSION" != "$TARGET_PYTHON_VERSION" ]; then
    echo -e "${YELLOW}  Warning: Python version mismatch!${NC}"
    echo "    Archive: Python $PYTHON_VERSION"
    echo "    Target:  Python $TARGET_PYTHON_VERSION"
    echo -e "${YELLOW}  The package may not work correctly.${NC}"
    read -p "  Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 1
    fi
fi

# Check architecture on target Pi
echo ""
echo -e "${BLUE}Step 2: Checking architecture on target Pi...${NC}"
TARGET_ARCH=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "uname -m")
echo "  Target architecture: $TARGET_ARCH"

if [ "$ARCH" != "unknown" ] && [ "$ARCH" != "$TARGET_ARCH" ]; then
    echo -e "${RED}  Error: Architecture mismatch!${NC}"
    echo "    Archive: $ARCH"
    echo "    Target:  $TARGET_ARCH"
    echo -e "${RED}  The package will not work on this architecture.${NC}"
    exit 1
fi

# Find site-packages directory on target Pi
echo ""
echo -e "${BLUE}Step 3: Locating site-packages directory...${NC}"
SITE_PACKAGES_DIR=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
    python3 -c 'import site; pkgs = site.getsitepackages(); print(pkgs[0] if pkgs else \"\")' 2>/dev/null || \
    python3 -c 'import sys; pkgs = [p for p in sys.path if \"site-packages\" in p]; print(pkgs[0] if pkgs else \"\")' 2>/dev/null || \
    echo ''
")

USER_SITE_PACKAGES_DIR=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
    python3 -c 'import site; print(site.getusersitepackages())' 2>/dev/null || echo ''
")

if [ -z "$SITE_PACKAGES_DIR" ] && [ -z "$USER_SITE_PACKAGES_DIR" ]; then
    echo -e "${RED}Error: Could not determine site-packages directory${NC}"
    exit 1
fi

echo "  System site-packages: ${SITE_PACKAGES_DIR:-not found}"
echo "  User site-packages: ${USER_SITE_PACKAGES_DIR:-not found}"

# Determine installation location based on preference
INSTALL_LOCATION=""
if [ "$INSTALL_PREFERENCE" == "system" ]; then
    if [ -n "$SITE_PACKAGES_DIR" ]; then
        INSTALL_LOCATION="$SITE_PACKAGES_DIR"
        USE_SUDO="sudo"
        echo "  Using system site-packages (sudo required)"
    else
        echo -e "${RED}Error: System site-packages directory not found${NC}"
        exit 1
    fi
else
    # Default to user site-packages
    if [ -n "$USER_SITE_PACKAGES_DIR" ]; then
        INSTALL_LOCATION="$USER_SITE_PACKAGES_DIR"
        USE_SUDO=""
        echo "  Using user site-packages (no sudo needed)"
    elif [ -n "$SITE_PACKAGES_DIR" ]; then
        # Fallback to system if user site-packages not available
        INSTALL_LOCATION="$SITE_PACKAGES_DIR"
        USE_SUDO="sudo"
        echo "  Using system site-packages (sudo required)"
    else
        echo -e "${RED}Error: No site-packages directory found${NC}"
        exit 1
    fi
fi

# Check if zeroconf is already installed
echo ""
echo -e "${BLUE}Step 4: Checking for existing zeroconf installation...${NC}"
EXISTING_VERSION=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
    python3 -c 'import zeroconf; print(zeroconf.__version__)' 2>/dev/null || echo ''
")

if [ -n "$EXISTING_VERSION" ]; then
    echo "  Found existing zeroconf version: $EXISTING_VERSION"
    if [ "$ZEROCONF_VERSION" != "unknown" ] && [ "$EXISTING_VERSION" == "$ZEROCONF_VERSION" ]; then
        echo -e "${YELLOW}  Same version already installed.${NC}"
        read -p "  Overwrite? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Installation cancelled."
            exit 0
        fi
    fi
    
    # Remove existing installation
    echo "  Removing existing installation..."
    sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
        $USE_SUDO rm -rf '$INSTALL_LOCATION/zeroconf' '$INSTALL_LOCATION/zeroconf-*.dist-info' 2>/dev/null || true
    "
fi

# Upload archive to Pi
echo ""
echo -e "${BLUE}Step 5: Uploading archive to Pi...${NC}"
REMOTE_ARCHIVE="/tmp/${ARCHIVE_NAME}"
sshpass -p "$PI_PASSWORD" scp $SCP_OPTS "$ARCHIVE_PATH" "${PI_USER}@${PI_SSH_HOST}:${REMOTE_ARCHIVE}" || {
    echo -e "${RED}Error: Failed to upload archive${NC}"
    exit 1
}
echo -e "${GREEN}  ✓ Archive uploaded${NC}"

# Install dependencies
echo ""
echo -e "${BLUE}Step 6: Installing dependencies...${NC}"
echo "  Checking for ifaddr..."
IFADDR_INSTALLED=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
    python3 -c 'import ifaddr' 2>/dev/null && echo 'true' || echo 'false'
")

if [ "$IFADDR_INSTALLED" != "true" ]; then
    echo "  Installing ifaddr..."
    if [ -z "$USE_SUDO" ]; then
        # User installation - need both --user and --break-system-packages on newer Raspberry Pi OS
        sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
            pip3 install --user --break-system-packages ifaddr
        " || {
            echo -e "${RED}Error: Failed to install ifaddr${NC}"
            exit 1
        }
    else
        # System installation
        sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
            $USE_SUDO pip3 install --break-system-packages ifaddr
        " || {
            echo -e "${RED}Error: Failed to install ifaddr${NC}"
            exit 1
        }
    fi
    echo -e "${GREEN}  ✓ ifaddr installed${NC}"
else
    echo -e "${GREEN}  ✓ ifaddr already installed${NC}"
fi

# Extract archive on Pi
echo ""
echo -e "${BLUE}Step 7: Extracting archive...${NC}"
sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
    # Ensure target directory exists
    if [ -n '$USE_SUDO' ]; then
        $USE_SUDO mkdir -p '$INSTALL_LOCATION'
    else
        mkdir -p '$INSTALL_LOCATION'
    fi
    
    # Extract archive
    cd '$INSTALL_LOCATION'
    $USE_SUDO tar -xzf '$REMOTE_ARCHIVE' || {
        echo 'Error: Failed to extract archive'
        exit 1
    }
    echo 'Archive extracted successfully'
" || {
    echo -e "${RED}Error: Failed to extract archive${NC}"
    exit 1
}
echo -e "${GREEN}  ✓ Archive extracted${NC}"

# Clean up remote archive
echo ""
echo -e "${BLUE}Step 8: Cleaning up...${NC}"
sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "rm -f '$REMOTE_ARCHIVE'" 2>/dev/null || true

# Verify installation
echo ""
echo -e "${BLUE}Step 9: Verifying installation...${NC}"
INSTALLED_VERSION=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
    python3 -c 'import zeroconf; print(zeroconf.__version__)' 2>/dev/null || echo ''
")

if [ -n "$INSTALLED_VERSION" ]; then
    echo -e "${GREEN}  ✓ zeroconf installed successfully!${NC}"
    echo "  Installed version: $INSTALLED_VERSION"
    
    # Test import
    echo ""
    echo "Testing import..."
    TEST_RESULT=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
        python3 -c 'from zeroconf import ServiceInfo, Zeroconf; print(\"OK\")' 2>&1
    ")
    
    if [[ "$TEST_RESULT" == "OK" ]]; then
        echo -e "${GREEN}  ✓ Import test passed${NC}"
    else
        echo -e "${YELLOW}  Warning: Import test failed${NC}"
        echo "    $TEST_RESULT"
    fi
else
    echo -e "${RED}  Error: Installation verification failed${NC}"
    echo "    zeroconf could not be imported"
    exit 1
fi

echo ""
echo -e "${GREEN}✓ Installation complete!${NC}"
echo ""
echo "zeroconf is now installed and ready to use."
echo "You can test it by running:"
echo "  ssh ${PI_USER}@${PI_SSH_HOST}"
echo "  python3 -c 'from zeroconf import ServiceInfo, Zeroconf; print(\"zeroconf is working!\")'"

