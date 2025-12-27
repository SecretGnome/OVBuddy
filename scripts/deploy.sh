#!/bin/bash

# Deployment script for ovbuddy to Raspberry Pi
# Reads credentials from .env file
# Deploys all files from the dist/ folder
# Usage: ./scripts/deploy.sh [-main] [-reboot] [-skip-deploy]
#   -main        : deploy only ovbuddy.py
#   -reboot      : reboot device after deployment and check service status
#   -skip-deploy : skip file deployment, but continue with Python deps and rest of setup

# Change to project root directory (parent of scripts/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

set -e  # Exit on error

# Define timeout function that works on macOS and Linux
# macOS doesn't have timeout by default, so we create a wrapper
if command -v timeout &> /dev/null || command -v gtimeout &> /dev/null; then
    # Use native timeout if available
    if command -v timeout &> /dev/null; then
        TIMEOUT_CMD="timeout"
    else
        TIMEOUT_CMD="gtimeout"
    fi
else
    # Fallback: create a timeout wrapper using background process (works on macOS)
    timeout() {
        local duration=$1
        shift
        local cmd="$@"
        
        # Run command in background
        eval "$cmd" &
        local cmd_pid=$!
        
        # Wait for specified duration
        local count=0
        while [ $count -lt $duration ]; do
            if ! kill -0 $cmd_pid 2>/dev/null; then
                # Process finished, get exit code
                wait $cmd_pid
                return $?
            fi
            sleep 1
            count=$((count + 1))
        done
        
        # Timeout reached, kill the process
        kill $cmd_pid 2>/dev/null
        wait $cmd_pid 2>/dev/null
        return 124  # Standard timeout exit code
    }
    TIMEOUT_CMD="timeout"
fi

# Check for arguments
DEPLOY_MAIN_ONLY=false
REBOOT_AFTER=false
SKIP_DEPLOY=false
for arg in "$@"; do
    if [ "$arg" == "-main" ]; then
        DEPLOY_MAIN_ONLY=true
    elif [ "$arg" == "-reboot" ]; then
        REBOOT_AFTER=true
    elif [ "$arg" == "-skip-deploy" ] || [ "$arg" == "--skip-deploy" ]; then
        SKIP_DEPLOY=true
    fi
done

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Load environment variables from .env file (check current dir, then parent dir)
if [ -f ".env" ]; then
    set -a
    source .env
    set +a
elif [ -f "../.env" ]; then
    set -a
    source ../.env
    set +a
fi

# Validate required variables
if [ -z "$PI_HOST" ] || [ -z "$PI_USER" ] || [ -z "$PI_PASSWORD" ]; then
    echo -e "${RED}Error: PI_HOST, PI_USER, and PI_PASSWORD must be set in .env file${NC}"
    echo "Create a .env file in the scripts/ or project root directory with:"
    echo "  PI_HOST=192.168.1.xxx"
    echo "  PI_USER=pi"
    echo "  PI_PASSWORD=your_password"
    exit 1
fi

# Check if sshpass is installed (needed for password auth)
if ! command -v sshpass &> /dev/null; then
    echo -e "${RED}Error: sshpass is required for password authentication${NC}"
    echo "Install it with:"
    echo "  macOS: brew install hudochenkov/sshpass/sshpass"
    echo "  Linux: apt-get install sshpass"
    exit 1
fi

# Check if dist folder exists (in current dir or parent dir)
if [ -d "dist" ]; then
    DIST_DIR="dist"
elif [ -d "../dist" ]; then
    DIST_DIR="../dist"
else
    echo -e "${RED}Error: dist/ folder not found!${NC}"
    echo "Please create the dist/ folder and copy deployment files to it."
    exit 1
fi

# Remote directory
REMOTE_DIR="/home/${PI_USER}/ovbuddy"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=3 -o PreferredAuthentications=password -o PubkeyAuthentication=no"
SCP_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o PreferredAuthentications=password -o PubkeyAuthentication=no"

# Try to resolve IP if hostname is used
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

if [ "$SKIP_DEPLOY" == true ]; then
    echo -e "${YELLOW}Skipping file deployment (continuing with Python deps and setup)...${NC}"
    echo -e "${YELLOW}Connecting to ${PI_USER}@${PI_SSH_HOST}...${NC}"
    # Still ensure remote directory exists (needed for zeroconf package copy)
    sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "mkdir -p ${REMOTE_DIR}" > /dev/null 2>&1

    echo ""
else
    echo -e "${YELLOW}Deploying ovbuddy to ${PI_USER}@${PI_SSH_HOST}:${REMOTE_DIR}${NC}"

    # Create remote directory if it doesn't exist
    echo "Creating remote directory..."
    sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "mkdir -p ${REMOTE_DIR}"

    # Copy files to Raspberry Pi
    if [ "$DEPLOY_MAIN_ONLY" == true ]; then
    echo "Deploying only ovbuddy.py..."
    if [ ! -f "$DIST_DIR/ovbuddy.py" ]; then
        echo -e "${RED}Error: $DIST_DIR/ovbuddy.py not found!${NC}"
        exit 1
    fi
    echo "  → ovbuddy.py"
    sshpass -p "$PI_PASSWORD" scp $SCP_OPTS "$DIST_DIR/ovbuddy.py" "${PI_USER}@${PI_SSH_HOST}:${REMOTE_DIR}/"
    
    # Safety: ensure web UI assets exist (templates + static). This prevents empty/missing templates when iterating with -main.
    if [ -d "$DIST_DIR/templates" ]; then
        echo "  → templates/ (directory)"
        sshpass -p "$PI_PASSWORD" scp $SCP_OPTS -r "$DIST_DIR/templates" "${PI_USER}@${PI_SSH_HOST}:${REMOTE_DIR}/"
    fi
    if [ -d "$DIST_DIR/static" ]; then
        echo "  → static/ (directory)"
        sshpass -p "$PI_PASSWORD" scp $SCP_OPTS -r "$DIST_DIR/static" "${PI_USER}@${PI_SSH_HOST}:${REMOTE_DIR}/"
    fi

    echo -e "${GREEN}ovbuddy.py deployed successfully!${NC}"
    echo ""
    echo "Note: -main deploys ovbuddy.py plus web UI assets (templates/static). To deploy everything, run without -main."
else
    echo "Copying files from $DIST_DIR/ folder..."
    
    # Deploy all files from dist folder
    for file in $DIST_DIR/*; do
        if [ -f "$file" ]; then
            filename=$(basename "$file")
            echo "  → $filename"
            sshpass -p "$PI_PASSWORD" scp $SCP_OPTS "$file" "${PI_USER}@${PI_SSH_HOST}:${REMOTE_DIR}/"
        fi
    done
    
    # Deploy templates and static directories if they exist
    if [ -d "$DIST_DIR/templates" ]; then
        echo "  → templates/ (directory)"
        sshpass -p "$PI_PASSWORD" scp $SCP_OPTS -r "$DIST_DIR/templates" "${PI_USER}@${PI_SSH_HOST}:${REMOTE_DIR}/"
    fi
    if [ -d "$DIST_DIR/static" ]; then
        echo "  → static/ (directory)"
        sshpass -p "$PI_PASSWORD" scp $SCP_OPTS -r "$DIST_DIR/static" "${PI_USER}@${PI_SSH_HOST}:${REMOTE_DIR}/"
    fi

    # Make scripts executable
    echo ""
    echo "Making scripts executable..."
    sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "cd ${REMOTE_DIR} && chmod +x *.sh 2>/dev/null || true"
    fi
fi

# Install Python dependencies if requirements.txt exists
# Always run this unless we're doing -main only (which skips deps)
if [ "$DEPLOY_MAIN_ONLY" != true ]; then
    # Install Python dependencies - check each package individually
    if [ -f "$DIST_DIR/requirements.txt" ]; then
        echo ""
        echo -e "${YELLOW}Checking Python dependencies...${NC}"
        
        # Check if core tools are installed
        # Git is required for the on-device auto-updater (it uses `git clone`).
        GIT_INSTALLED=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "command -v git >/dev/null 2>&1 && echo 'true' || echo 'false'")
        PYTHON3_INSTALLED=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "command -v python3 >/dev/null 2>&1 && echo 'true' || echo 'false'")
        PIP3_INSTALLED=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "command -v pip3 >/dev/null 2>&1 && echo 'true' || echo 'false'")

        # Ensure git is installed regardless of python/pip status
        if [ "$GIT_INSTALLED" = "false" ]; then
            echo -e "${YELLOW}  Installing git (required for auto-updates)...${NC}"
            sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "sudo apt-get update && sudo apt-get install -y git" || {
                echo -e "${RED}  ✗ Failed to install git${NC}"
                exit 1
            }
            echo -e "${GREEN}  ✓ Git installed${NC}"
        else
            echo -e "${GREEN}  ✓ Git already installed${NC}"
        fi
        
        # Install system packages if python3 or pip3 is missing
        if [ "$PYTHON3_INSTALLED" = "false" ] || [ "$PIP3_INSTALLED" = "false" ]; then
            echo -e "${YELLOW}  Installing system packages (python3, pip3, GPIO/SPI)...${NC}"
            sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "sudo apt-get update && sudo apt-get install -y python3 python3-pip python3-pil python3-numpy libopenjp2-7 libtiff6 python3-rpi.gpio python3-spidev" || {
                echo -e "${RED}  ✗ Failed to install system packages${NC}"
                exit 1
            }
            echo -e "${GREEN}  ✓ System packages installed${NC}"
        else
            # Even if python3/pip3 are installed, ensure image processing libraries are present
            echo -e "${YELLOW}  Checking system image libraries...${NC}"
            
            # Check if libopenjp2-7 is installed (required for PIL/Pillow JPEG2000 support)
            LIBOPENJP2_INSTALLED=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "dpkg -l | grep -q 'libopenjp2-7' && echo 'true' || echo 'false'")
            
            if [ "$LIBOPENJP2_INSTALLED" != "true" ]; then
                echo -e "${YELLOW}    Installing libopenjp2-7 (required for PIL)...${NC}"
                sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "sudo apt-get update && sudo apt-get install -y libopenjp2-7" || {
                    echo -e "${YELLOW}    ⚠ Failed to install libopenjp2-7${NC}"
                }
            fi
            
            # Install other image libraries if missing
            sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "sudo apt-get install -y python3-pil python3-numpy libtiff6 2>/dev/null" || true
            
            # Install GPIO and SPI system packages (required for e-ink display)
            echo -e "${YELLOW}  Checking GPIO/SPI system packages...${NC}"
            sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "sudo apt-get install -y python3-rpi.gpio python3-spidev 2>/dev/null" || {
                echo -e "${YELLOW}    ⚠ Some GPIO/SPI packages may not be available (gpiozero/spidev should still work)${NC}"
            }
            echo -e "${GREEN}  ✓ System libraries checked${NC}"
        fi
        
        # Now check and install each Python package individually
        
        # Flask (required for web server)
        FLASK_INSTALLED=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "python3 -c 'import flask' 2>/dev/null && echo 'true' || echo 'false'")
        if [ "$FLASK_INSTALLED" != "true" ]; then
            echo -e "${YELLOW}  Installing Flask (web server)...${NC}"
            sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "cd ${REMOTE_DIR} && pip3 install --user flask 2>/dev/null" || \
            sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "cd ${REMOTE_DIR} && pip3 install --break-system-packages flask"
            echo -e "${GREEN}  ✓ Flask installed${NC}"
        else
            echo -e "${GREEN}  ✓ Flask already installed${NC}"
        fi
        
        # pyqrcode and pypng (required for QR code display)
        PYQRCODE_INSTALLED=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "python3 -c 'import pyqrcode' 2>/dev/null && echo 'true' || echo 'false'")
        if [ "$PYQRCODE_INSTALLED" != "true" ]; then
            echo -e "${YELLOW}  Installing pyqrcode and pypng (QR codes)...${NC}"
            sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "cd ${REMOTE_DIR} && pip3 install --user pyqrcode pypng 2>/dev/null" || \
            sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "cd ${REMOTE_DIR} && pip3 install --break-system-packages pyqrcode pypng"
            echo -e "${GREEN}  ✓ pyqrcode installed${NC}"
        else
            echo -e "${GREEN}  ✓ pyqrcode already installed${NC}"
        fi
        
        # Pillow (required for image processing)
        PILLOW_INSTALLED=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "python3 -c 'from PIL import Image' 2>/dev/null && echo 'true' || echo 'false'")
        if [ "$PILLOW_INSTALLED" != "true" ]; then
            echo -e "${YELLOW}  Installing Pillow (image processing)...${NC}"
            sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "cd ${REMOTE_DIR} && pip3 install --user Pillow 2>/dev/null" || \
            sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "cd ${REMOTE_DIR} && pip3 install --break-system-packages Pillow"
            echo -e "${GREEN}  ✓ Pillow installed${NC}"
        else
            echo -e "${GREEN}  ✓ Pillow already installed${NC}"
        fi
        
        # requests (required for API calls)
        REQUESTS_INSTALLED=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "python3 -c 'import requests' 2>/dev/null && echo 'true' || echo 'false'")
        if [ "$REQUESTS_INSTALLED" != "true" ]; then
            echo -e "${YELLOW}  Installing requests (API calls)...${NC}"
            sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "cd ${REMOTE_DIR} && pip3 install --user requests 2>/dev/null" || \
            sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "cd ${REMOTE_DIR} && pip3 install --break-system-packages requests"
            echo -e "${GREEN}  ✓ requests installed${NC}"
        else
            echo -e "${GREEN}  ✓ requests already installed${NC}"
        fi
        
        # gpiozero (required for GPIO control)
        GPIOZERO_INSTALLED=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "python3 -c 'import gpiozero' 2>/dev/null && echo 'true' || echo 'false'")
        if [ "$GPIOZERO_INSTALLED" != "true" ]; then
            echo -e "${YELLOW}  Installing gpiozero (GPIO control)...${NC}"
            sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "cd ${REMOTE_DIR} && pip3 install --user gpiozero 2>/dev/null" || \
            sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "cd ${REMOTE_DIR} && pip3 install --break-system-packages gpiozero"
            echo -e "${GREEN}  ✓ gpiozero installed${NC}"
        else
            echo -e "${GREEN}  ✓ gpiozero already installed${NC}"
        fi
        
        # spidev (required for SPI communication with e-ink display)
        SPIDEV_INSTALLED=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "python3 -c 'import spidev' 2>/dev/null && echo 'true' || echo 'false'")
        if [ "$SPIDEV_INSTALLED" != "true" ]; then
            echo -e "${YELLOW}  Installing spidev (SPI communication for e-ink)...${NC}"
            sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "cd ${REMOTE_DIR} && pip3 install --user spidev 2>/dev/null" || \
            sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "cd ${REMOTE_DIR} && pip3 install --break-system-packages spidev"
            echo -e "${GREEN}  ✓ spidev installed${NC}"
        else
            echo -e "${GREEN}  ✓ spidev already installed${NC}"
        fi
        
        # lgpio (required for GPIO cleanup)
        LGPIO_INSTALLED=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "python3 -c 'import lgpio' 2>/dev/null && echo 'true' || echo 'false'")
        if [ "$LGPIO_INSTALLED" != "true" ]; then
            echo -e "${YELLOW}  Installing lgpio (GPIO cleanup)...${NC}"
            sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "cd ${REMOTE_DIR} && pip3 install --user lgpio 2>/dev/null" || \
            sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "cd ${REMOTE_DIR} && pip3 install --break-system-packages lgpio"
            echo -e "${GREEN}  ✓ lgpio installed${NC}"
        else
            echo -e "${GREEN}  ✓ lgpio already installed${NC}"
        fi
        
        # zeroconf (optional, for Bonjour/mDNS support)
        ZEROCONF_INSTALLED=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "python3 -c 'import zeroconf' 2>/dev/null && echo 'true' || echo 'false'")
        if [ "$ZEROCONF_INSTALLED" != "true" ]; then
            # Check if we have a pre-built package
            ZEROCONF_PKG=$(find "$PROJECT_ROOT/retrieved-packages" -name "zeroconf-*.tar.gz" 2>/dev/null | head -1)
            
            if [ -n "$ZEROCONF_PKG" ] && [ -f "$ZEROCONF_PKG" ]; then
                echo -e "${YELLOW}  Installing zeroconf from pre-built package...${NC}"
                
                # Get user site-packages directory
                USER_SITE_PACKAGES=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "python3 -c 'import site; print(site.getusersitepackages())' 2>/dev/null")
                
                if [ -n "$USER_SITE_PACKAGES" ]; then
                    echo -e "${YELLOW}    Target directory: ${USER_SITE_PACKAGES}${NC}"
                    
                    # Install ifaddr dependency first (required by zeroconf)
                    echo -e "${YELLOW}    Checking for ifaddr dependency...${NC}"
                    IFADDR_INSTALLED=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "python3 -c 'import ifaddr' 2>/dev/null && echo 'true' || echo 'false'")
                    
                    if [ "$IFADDR_INSTALLED" != "true" ]; then
                        echo -e "${YELLOW}    Installing ifaddr...${NC}"
                        # Use both --user and --break-system-packages for newer Raspberry Pi OS (PEP 668 compliance)
                        if sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "pip3 install --user --break-system-packages ifaddr" 2>/dev/null; then
                            echo -e "${GREEN}    ✓ ifaddr installed${NC}"
                        else
                            echo -e "${YELLOW}    ⚠ Failed to install ifaddr (zeroconf may not work)${NC}"
                        fi
                    else
                        echo -e "${GREEN}    ✓ ifaddr already installed${NC}"
                    fi
                    
                    # Upload archive to Pi
                    ARCHIVE_NAME=$(basename "$ZEROCONF_PKG")
                    REMOTE_ARCHIVE="/tmp/${ARCHIVE_NAME}"
                    echo -e "${YELLOW}    Uploading ${ARCHIVE_NAME}...${NC}"
                    
                    if ! sshpass -p "$PI_PASSWORD" scp $SCP_OPTS "$ZEROCONF_PKG" "${PI_USER}@${PI_SSH_HOST}:${REMOTE_ARCHIVE}" 2>&1; then
                        echo -e "${RED}    ✗ Failed to upload archive${NC}"
                    else
                        echo -e "${GREEN}    ✓ Archive uploaded${NC}"
                        
                        # Extract directly to user site-packages
                        echo -e "${YELLOW}    Extracting to site-packages...${NC}"
                        EXTRACT_RESULT=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
                            mkdir -p '$USER_SITE_PACKAGES' && \
                            cd '$USER_SITE_PACKAGES' && \
                            tar -xzf '$REMOTE_ARCHIVE' 2>&1 && \
                            rm -f '$REMOTE_ARCHIVE' && \
                            echo 'SUCCESS'
                        " 2>&1)
                        
                        if echo "$EXTRACT_RESULT" | grep -q "SUCCESS"; then
                            echo -e "${GREEN}    ✓ Archive extracted${NC}"
                            
                            # Verify installation
                            ZEROCONF_INSTALLED=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "python3 -c 'import zeroconf; print(zeroconf.__version__)' 2>&1")
                            if [ $? -eq 0 ]; then
                                echo -e "${GREEN}  ✓ zeroconf installed (version: ${ZEROCONF_INSTALLED})${NC}"
                            else
                                echo -e "${YELLOW}  ⚠ zeroconf installation failed${NC}"
                                echo -e "${YELLOW}    Import error: ${ZEROCONF_INSTALLED}${NC}"
                            fi
                        else
                            echo -e "${RED}    ✗ Failed to extract archive${NC}"
                            echo -e "${RED}    Error: ${EXTRACT_RESULT}${NC}"
                        fi
                    fi
                else
                    echo -e "${YELLOW}  ⚠ Could not determine site-packages directory${NC}"
                fi
            else
                echo -e "${YELLOW}  ⚠ zeroconf not installed (optional, takes 15+ min to build)${NC}"
                echo -e "${YELLOW}     To install: run ./scripts/retrieve-zeroconf.sh then re-deploy${NC}"
            fi
        else
            echo -e "${GREEN}  ✓ zeroconf already installed${NC}"
        fi
    fi
    
    # Enable SPI interface (required for e-ink display) - always check/enable
    echo ""
    echo -e "${YELLOW}Checking SPI interface configuration...${NC}"
    SPI_RESULT=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
        # Check both possible config.txt locations (older and newer Pi OS)
        CONFIG_FILE=''
        if [ -f /boot/firmware/config.txt ]; then
            CONFIG_FILE='/boot/firmware/config.txt'
        elif [ -f /boot/config.txt ]; then
            CONFIG_FILE='/boot/config.txt'
        fi
        
        if [ -z \"\$CONFIG_FILE\" ]; then
            echo 'ERROR: Could not find config.txt'
            exit 1
        fi
        
        # Check if SPI is already enabled in config
        SPI_IN_CONFIG=false
        if grep -q '^dtparam=spi=on' \"\$CONFIG_FILE\" 2>/dev/null; then
            SPI_IN_CONFIG=true
        fi
        
        # Check if SPI device files exist (means SPI is actually working)
        SPI_DEVICE_EXISTS=false
        if [ -e /dev/spidev0.0 ] || [ -e /dev/spidev0.1 ]; then
            SPI_DEVICE_EXISTS=true
        fi
        
        # Check if SPI kernel module is loaded
        SPI_MODULE_LOADED=false
        if lsmod | grep -q '^spi_' 2>/dev/null; then
            SPI_MODULE_LOADED=true
        fi
        
        # Try to load SPI module if not loaded
        if [ \"\$SPI_MODULE_LOADED\" = false ]; then
            sudo modprobe spi_bcm2835 2>/dev/null || sudo modprobe spi_bcm2835 2>/dev/null || true
            sleep 1
            if lsmod | grep -q '^spi_' 2>/dev/null; then
                SPI_MODULE_LOADED=true
            fi
        fi
        
        # Enable SPI in config if not already enabled
        if [ \"\$SPI_IN_CONFIG\" = false ]; then
            echo 'dtparam=spi=on' | sudo tee -a \"\$CONFIG_FILE\" > /dev/null
            echo 'ENABLED_IN_CONFIG'
        else
            echo 'ALREADY_IN_CONFIG'
        fi
        
        # Report status
        if [ \"\$SPI_DEVICE_EXISTS\" = true ]; then
            echo 'DEVICE_EXISTS'
        else
            echo 'DEVICE_MISSING'
        fi
        
        if [ \"\$SPI_MODULE_LOADED\" = true ]; then
            echo 'MODULE_LOADED'
        else
            echo 'MODULE_NOT_LOADED'
        fi
    " 2>&1)
    
    # Parse results
    if echo "$SPI_RESULT" | grep -q "ALREADY_IN_CONFIG"; then
        echo -e "${GREEN}  ✓ SPI interface enabled in config.txt${NC}"
    elif echo "$SPI_RESULT" | grep -q "ENABLED_IN_CONFIG"; then
        echo -e "${GREEN}  ✓ SPI interface enabled in config.txt${NC}"
        echo -e "${YELLOW}  ⚠ Reboot required for SPI to take effect${NC}"
    elif echo "$SPI_RESULT" | grep -q "ERROR"; then
        echo -e "${YELLOW}  ⚠ Could not find config.txt - SPI may need manual configuration${NC}"
    fi
    
    # Check if SPI device files exist
    if echo "$SPI_RESULT" | grep -q "DEVICE_EXISTS"; then
        echo -e "${GREEN}  ✓ SPI device files found (/dev/spidev0.*)${NC}"
    elif echo "$SPI_RESULT" | grep -q "DEVICE_MISSING"; then
        echo -e "${YELLOW}  ⚠ SPI device files not found${NC}"
        if echo "$SPI_RESULT" | grep -q "MODULE_LOADED"; then
            echo -e "${YELLOW}     SPI module is loaded but devices missing - reboot may be required${NC}"
        else
            echo -e "${YELLOW}     SPI module not loaded - reboot required${NC}"
        fi
    fi
    
    if echo "$SPI_RESULT" | grep -q "MODULE_LOADED"; then
        echo -e "${GREEN}  ✓ SPI kernel module is loaded${NC}"
    elif echo "$SPI_RESULT" | grep -q "MODULE_NOT_LOADED"; then
        echo -e "${YELLOW}  ⚠ SPI kernel module not loaded - reboot required${NC}"
    fi
    
    # Final warning if SPI is not fully working
    if echo "$SPI_RESULT" | grep -q "DEVICE_MISSING"; then
        echo ""
        echo -e "${YELLOW}  ⚠ SPI is not fully functional. To fix:${NC}"
        echo -e "${YELLOW}     1. Reboot the Pi: sudo reboot${NC}"
        echo -e "${YELLOW}     2. After reboot, verify: ls -l /dev/spidev*${NC}"
        echo -e "${YELLOW}     3. You should see /dev/spidev0.0 and /dev/spidev0.1${NC}"
    fi
fi

# Setup / refresh passwordless sudo configuration (required for web actions + auto-update reboot)
echo ""
echo -e "${YELLOW}Checking passwordless sudo configuration...${NC}"
PASSWORDLESS_SUDO=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "sudo -n echo 'test' > /dev/null 2>&1 && echo 'true' || echo 'false'" 2>/dev/null)

echo -e "${YELLOW}Preparing sudoers rules...${NC}"
# Create sudoers configuration for passwordless sudo (we may install/refresh it below)
SUDOERS_CONTENT="# OVBuddy passwordless sudo configuration
# Allows OVBuddy service to perform necessary system operations

# Allow systemctl commands for ovbuddy services
${PI_USER} ALL=(ALL) NOPASSWD: /bin/systemctl start ovbuddy
${PI_USER} ALL=(ALL) NOPASSWD: /bin/systemctl stop ovbuddy
${PI_USER} ALL=(ALL) NOPASSWD: /bin/systemctl restart ovbuddy
${PI_USER} ALL=(ALL) NOPASSWD: /bin/systemctl status ovbuddy
${PI_USER} ALL=(ALL) NOPASSWD: /bin/systemctl enable ovbuddy
${PI_USER} ALL=(ALL) NOPASSWD: /bin/systemctl disable ovbuddy
${PI_USER} ALL=(ALL) NOPASSWD: /bin/systemctl start ovbuddy-web
${PI_USER} ALL=(ALL) NOPASSWD: /bin/systemctl stop ovbuddy-web
${PI_USER} ALL=(ALL) NOPASSWD: /bin/systemctl restart ovbuddy-web
${PI_USER} ALL=(ALL) NOPASSWD: /bin/systemctl status ovbuddy-web
${PI_USER} ALL=(ALL) NOPASSWD: /bin/systemctl enable ovbuddy-web
${PI_USER} ALL=(ALL) NOPASSWD: /bin/systemctl disable ovbuddy-web
${PI_USER} ALL=(ALL) NOPASSWD: /bin/systemctl daemon-reload

# Allow reboot (used after successful auto-update)
${PI_USER} ALL=(ALL) NOPASSWD: /bin/systemctl reboot
${PI_USER} ALL=(ALL) NOPASSWD: /sbin/reboot
${PI_USER} ALL=(ALL) NOPASSWD: /usr/sbin/reboot

# Allow network configuration commands
${PI_USER} ALL=(ALL) NOPASSWD: /sbin/iwlist * scan
${PI_USER} ALL=(ALL) NOPASSWD: /sbin/wpa_cli *
${PI_USER} ALL=(ALL) NOPASSWD: /usr/bin/wpa_cli *
${PI_USER} ALL=(ALL) NOPASSWD: /bin/systemctl restart wpa_supplicant
${PI_USER} ALL=(ALL) NOPASSWD: /bin/systemctl restart dhcpcd
${PI_USER} ALL=(ALL) NOPASSWD: /sbin/dhclient *
${PI_USER} ALL=(ALL) NOPASSWD: /usr/sbin/dhclient *
${PI_USER} ALL=(ALL) NOPASSWD: /usr/bin/tee /etc/wpa_supplicant/wpa_supplicant.conf
${PI_USER} ALL=(ALL) NOPASSWD: /usr/bin/tee /etc/wpa_supplicant/wpa_supplicant-wlan0.conf
${PI_USER} ALL=(ALL) NOPASSWD: /bin/cat /etc/wpa_supplicant/wpa_supplicant.conf
${PI_USER} ALL=(ALL) NOPASSWD: /bin/cat /etc/wpa_supplicant/wpa_supplicant-wlan0.conf
${PI_USER} ALL=(ALL) NOPASSWD: /usr/bin/test -f /etc/wpa_supplicant/*
${PI_USER} ALL=(ALL) NOPASSWD: /bin/mkdir -p /etc/wpa_supplicant

# Allow Bonjour/mDNS configuration
${PI_USER} ALL=(ALL) NOPASSWD: /bin/systemctl * avahi-daemon
${PI_USER} ALL=(ALL) NOPASSWD: /bin/sed -i * /etc/hosts

# Allow viewing logs
${PI_USER} ALL=(ALL) NOPASSWD: /bin/journalctl *

# Allow WiFi monitor service control
${PI_USER} ALL=(ALL) NOPASSWD: /bin/systemctl * ovbuddy-wifi
${PI_USER} ALL=(ALL) NOPASSWD: /bin/systemctl is-active ovbuddy-wifi
${PI_USER} ALL=(ALL) NOPASSWD: /bin/systemctl is-enabled ovbuddy-wifi

# Allow force AP mode script (runs as root, needs full access)
${PI_USER} ALL=(ALL) NOPASSWD: /usr/bin/bash ${REMOTE_DIR}/force-ap-mode.sh
${PI_USER} ALL=(ALL) NOPASSWD: /bin/bash ${REMOTE_DIR}/force-ap-mode.sh

# Allow install-all-services.sh to run (needs full sudo for service installation)
# This script copies files to /etc/systemd/system/ and /usr/local/bin/, runs apt-get, etc.
# Use absolute path - sudoers needs exact path matching
${PI_USER} ALL=(ALL) NOPASSWD: /usr/bin/bash /home/${PI_USER}/ovbuddy/install-all-services.sh
${PI_USER} ALL=(ALL) NOPASSWD: /bin/bash /home/${PI_USER}/ovbuddy/install-all-services.sh

# Allow install-service.sh to run (used by auto-updater)
${PI_USER} ALL=(ALL) NOPASSWD: /usr/bin/bash /home/${PI_USER}/ovbuddy/install-service.sh
${PI_USER} ALL=(ALL) NOPASSWD: /bin/bash /home/${PI_USER}/ovbuddy/install-service.sh

# Allow copying files to system directories (needed for service installation)
# and writing the SD-card-root web auth file (/boot*/ovbuddy-web-auth.txt)
${PI_USER} ALL=(ALL) NOPASSWD: /bin/cp
${PI_USER} ALL=(ALL) NOPASSWD: /usr/bin/cp

# Allow apt-get commands (needed for WiFi dependencies)
${PI_USER} ALL=(ALL) NOPASSWD: /usr/bin/apt-get

# Allow pkill commands (needed to stop stray processes)
${PI_USER} ALL=(ALL) NOPASSWD: /usr/bin/pkill
${PI_USER} ALL=(ALL) NOPASSWD: /bin/pkill

# Allow chmod commands
${PI_USER} ALL=(ALL) NOPASSWD: /bin/chmod
${PI_USER} ALL=(ALL) NOPASSWD: /usr/bin/chmod
"

install_or_refresh_sudoers() {
    echo -e "${YELLOW}  Installing/updating sudoers rules...${NC}"
    # First, upload the sudoers content to a temp file
    echo "$SUDOERS_CONTENT" | sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "cat > /tmp/ovbuddy-sudoers"
    # Create a script that validates and installs sudoers
    sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "cat > /tmp/install-sudoers.sh" << 'INSTALL_SCRIPT_EOF'
#!/bin/bash
# Read password from first argument
PASSWORD="$1"

# Validate sudoers syntax using password
if echo "$PASSWORD" | sudo -S visudo -c -f /tmp/ovbuddy-sudoers 2>/dev/null; then
    # Install the file
    echo "$PASSWORD" | sudo -S cp /tmp/ovbuddy-sudoers /etc/sudoers.d/ovbuddy 2>/dev/null && \
    echo "$PASSWORD" | sudo -S chmod 0440 /etc/sudoers.d/ovbuddy 2>/dev/null && \
    echo "$PASSWORD" | sudo -S chown root:root /etc/sudoers.d/ovbuddy 2>/dev/null && \
    rm /tmp/ovbuddy-sudoers && \
    rm /tmp/install-sudoers.sh && \
    echo 'SUCCESS'
else
    echo 'FAILED: visudo validation failed'
    rm /tmp/ovbuddy-sudoers
    rm /tmp/install-sudoers.sh
    exit 1
fi
INSTALL_SCRIPT_EOF
    # Make script executable and run it with password as argument
    sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "chmod +x /tmp/install-sudoers.sh" > /dev/null 2>&1
    RESULT=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "/tmp/install-sudoers.sh '${PI_PASSWORD}'" 2>&1)
    if echo "$RESULT" | grep -q "SUCCESS"; then
        echo -e "${GREEN}  ✓ Sudoers rules installed/updated${NC}"
        sleep 1
        PASSWORDLESS_SUDO=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "sudo -n echo 'test' > /dev/null 2>&1 && echo 'true' || echo 'false'" 2>/dev/null)
        if [ "$PASSWORDLESS_SUDO" != "true" ]; then
            echo -e "${YELLOW}  ⚠ Sudoers installed but passwordless sudo check failed${NC}"
            PASSWORDLESS_SUDO="false"
        fi
    else
        echo -e "${YELLOW}  ⚠ Could not install/update sudoers${NC}"
        if [ -n "$RESULT" ]; then
            echo -e "${YELLOW}     Error: $(echo "$RESULT" | head -1)${NC}"
        fi
        PASSWORDLESS_SUDO="false"
    fi
}

if [ "$PASSWORDLESS_SUDO" != "true" ]; then
    echo -e "${YELLOW}  Passwordless sudo not enabled yet; configuring...${NC}"
    install_or_refresh_sudoers
else
    echo -e "${GREEN}  ✓ Passwordless sudo is enabled${NC}"
    # Even if passwordless sudo is enabled, ensure required rules exist (reboot + install-service.sh + cp for /boot*/ovbuddy-web-auth.txt).
    NEED_RULES=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "sudo -n grep -q '/bin/systemctl reboot' /etc/sudoers.d/ovbuddy 2>/dev/null && sudo -n grep -q 'install-service\\.sh' /etc/sudoers.d/ovbuddy 2>/dev/null && sudo -n grep -q '/bin/cp' /etc/sudoers.d/ovbuddy 2>/dev/null && echo 'false' || echo 'true'" 2>/dev/null || echo 'true')
    if [ "$NEED_RULES" = "true" ]; then
        echo -e "${YELLOW}  Updating sudoers to include reboot/update/cp rules...${NC}"
        install_or_refresh_sudoers
    else
        echo -e "${GREEN}  ✓ Sudoers rules already include reboot/update/cp permissions${NC}"
    fi
fi

# Fix Bonjour/mDNS setup (always run, regardless of PI_HOST format or deployment type)
echo ""
echo -e "${YELLOW}Fixing Bonjour/mDNS setup...${NC}"

# First, ensure avahi-daemon is installed
echo "  Checking if avahi-daemon is installed..."
AVAHI_INSTALLED=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "dpkg -l | grep -q avahi-daemon && echo 'true' || echo 'false'" 2>/dev/null)

if [ "$AVAHI_INSTALLED" != "true" ]; then
    echo -e "${YELLOW}  avahi-daemon not found, installing...${NC}"
    if [ "$PASSWORDLESS_SUDO" = "true" ]; then
        sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
            sudo -n apt-get update -qq 2>/dev/null && \
            sudo -n apt-get install -y avahi-daemon 2>/dev/null && \
            echo '✓ avahi-daemon installed'
        " 2>/dev/null || {
            echo -e "${YELLOW}  ⚠ Could not install avahi-daemon${NC}"
        }
    else
        $TIMEOUT_CMD 60 sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
            sudo apt-get update -qq 2>/dev/null && \
            sudo apt-get install -y avahi-daemon 2>/dev/null && \
            echo '✓ avahi-daemon installed'
        " 2>/dev/null || {
            echo -e "${YELLOW}  ⚠ Could not install avahi-daemon (may require passwordless sudo or timed out)${NC}"
        }
    fi
else
    echo -e "${GREEN}  ✓ avahi-daemon already installed${NC}"
fi

# Remove .local entries from /etc/hosts that interfere with mDNS
if [ "$PASSWORDLESS_SUDO" = "true" ]; then
    sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
        sudo -n sed -i '/\.local/d' /etc/hosts 2>/dev/null || true
        echo '✓ Removed .local entries from /etc/hosts'
    " 2>/dev/null || {
        echo -e "${YELLOW}  ⚠ Could not remove .local entries${NC}"
    }
else
    $TIMEOUT_CMD 10 sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
        sudo sed -i '/\.local/d' /etc/hosts 2>/dev/null || true
        echo '✓ Removed .local entries from /etc/hosts'
    " 2>/dev/null || {
        echo -e "${YELLOW}  ⚠ Could not remove .local entries (may require passwordless sudo or timed out)${NC}"
    }
fi

# Ensure avahi-daemon is enabled and running
if [ "$PASSWORDLESS_SUDO" = "true" ]; then
    sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
        sudo -n systemctl enable avahi-daemon 2>/dev/null && \
        sudo -n systemctl start avahi-daemon 2>/dev/null && \
        echo '✓ avahi-daemon enabled and started'
    " 2>/dev/null || {
        echo -e "${YELLOW}  ⚠ Could not enable/start avahi-daemon${NC}"
    }
else
    $TIMEOUT_CMD 10 sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
        sudo systemctl enable avahi-daemon 2>/dev/null && \
        sudo systemctl start avahi-daemon 2>/dev/null && \
        echo '✓ avahi-daemon enabled and started'
    " 2>/dev/null || {
        echo -e "${YELLOW}  ⚠ Could not enable/start avahi-daemon (may require passwordless sudo or timed out)${NC}"
    }
fi

# Restart avahi-daemon to ensure mDNS is working (non-blocking)
# Use try-restart which is non-blocking, run in background with short timeout
if [ "$PASSWORDLESS_SUDO" = "true" ]; then
    (sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
        sudo -n systemctl try-restart avahi-daemon 2>/dev/null || true
        echo '✓ avahi-daemon restart attempted'
    " 2>/dev/null &)
else
    ($TIMEOUT_CMD 10 sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
        sudo systemctl try-restart avahi-daemon 2>/dev/null || true
        echo '✓ avahi-daemon restart attempted'
    " 2>/dev/null &)
fi
# Wait max 3 seconds for the background process, then continue
sleep 3
wait 2>/dev/null || true

# Install persistent Bonjour fix (runs on boot)
if [ -f "$DIST_DIR/fix-bonjour.service" ]; then
    echo ""
    echo -e "${YELLOW}Installing persistent Bonjour fix (runs on boot)...${NC}"
    
    # Install service and timer using non-blocking commands with timeouts
    INSTALLED=false
    if [ "$PASSWORDLESS_SUDO" = "true" ]; then
        sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
            cd ${REMOTE_DIR} && \
            sudo -n cp fix-bonjour.service /etc/systemd/system/ 2>/dev/null && \
            echo '✓ Copied service file'
        " 2>/dev/null && INSTALLED=true || {
            echo -e "${YELLOW}  ⚠ Could not copy service file${NC}"
        }
    else
        $TIMEOUT_CMD 10 sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
            cd ${REMOTE_DIR} && \
            sudo cp fix-bonjour.service /etc/systemd/system/ 2>/dev/null && \
            echo '✓ Copied service file'
        " 2>/dev/null && INSTALLED=true || {
            echo -e "${YELLOW}  ⚠ Could not copy service file (may require passwordless sudo or timed out)${NC}"
        }
    fi
    
    # Copy timer if it exists
    if [ "$INSTALLED" = true ] && [ -f "$DIST_DIR/fix-bonjour.timer" ]; then
        if [ "$PASSWORDLESS_SUDO" = "true" ]; then
            sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
                cd ${REMOTE_DIR} && \
                sudo -n cp fix-bonjour.timer /etc/systemd/system/ 2>/dev/null && \
                echo '✓ Copied timer file'
            " 2>/dev/null || {
                echo -e "${YELLOW}  ⚠ Could not copy timer file${NC}"
            }
        else
            $TIMEOUT_CMD 10 sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
                cd ${REMOTE_DIR} && \
                sudo cp fix-bonjour.timer /etc/systemd/system/ 2>/dev/null && \
                echo '✓ Copied timer file'
            " 2>/dev/null || {
                echo -e "${YELLOW}  ⚠ Could not copy timer file (timed out)${NC}"
            }
        fi
    fi
    
    # Reload systemd and enable services (non-blocking with timeout)
    if [ "$INSTALLED" = true ]; then
        if [ "$PASSWORDLESS_SUDO" = "true" ]; then
            sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
                sudo -n systemctl daemon-reload 2>/dev/null && \
                sudo -n systemctl enable fix-bonjour.service 2>/dev/null && \
                sudo -n systemctl start fix-bonjour.service --no-block 2>/dev/null && \
                echo '✓ Service installed and started'
            " 2>/dev/null || {
                echo -e "${YELLOW}  ⚠ Could not enable/start service${NC}"
            }
        else
            $TIMEOUT_CMD 15 sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
                sudo systemctl daemon-reload 2>/dev/null && \
                sudo systemctl enable fix-bonjour.service 2>/dev/null && \
                sudo systemctl start fix-bonjour.service --no-block 2>/dev/null && \
                echo '✓ Service installed and started'
            " 2>/dev/null || {
                echo -e "${YELLOW}  ⚠ Could not enable/start service (may require passwordless sudo or timed out)${NC}"
            }
        fi
        
        # Enable and start timer if it exists
        if [ -f "$DIST_DIR/fix-bonjour.timer" ]; then
            if [ "$PASSWORDLESS_SUDO" = "true" ]; then
                sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
                    sudo -n systemctl enable fix-bonjour.timer 2>/dev/null && \
                    sudo -n systemctl start fix-bonjour.timer 2>/dev/null && \
                    echo '✓ Timer installed and started'
                " 2>/dev/null || {
                    echo -e "${YELLOW}  ⚠ Could not enable/start timer${NC}"
                }
            else
                $TIMEOUT_CMD 15 sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
                    sudo systemctl enable fix-bonjour.timer 2>/dev/null && \
                    sudo systemctl start fix-bonjour.timer 2>/dev/null && \
                    echo '✓ Timer installed and started'
                " 2>/dev/null || {
                    echo -e "${YELLOW}  ⚠ Could not enable/start timer (timed out)${NC}"
                }
            fi
        fi
        
        if [ "$INSTALLED" = true ]; then
            echo -e "${GREEN}  ✓ Persistent Bonjour fix installed${NC}"
        else
            if [ "$PASSWORDLESS_SUDO" != "true" ]; then
                echo -e "${YELLOW}  ⚠ Installation skipped (requires passwordless sudo)${NC}"
                echo -e "${YELLOW}  Passwordless sudo will be configured automatically on next deployment${NC}"
            else
                echo -e "${YELLOW}  ⚠ Installation failed (check error messages above)${NC}"
            fi
        fi
    fi
fi

echo -e "${GREEN}  ✓ Bonjour/mDNS fix applied${NC}"
echo -e "${YELLOW}  Note: You may need to flush DNS cache on your Mac:${NC}"
echo -e "${YELLOW}    sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder${NC}"

# Install/reinstall systemd services (ovbuddy, ovbuddy-web, ovbuddy-wifi, and fix-bonjour)
if [ -f "$DIST_DIR/install-all-services.sh" ]; then
    echo ""
    echo -e "${YELLOW}Installing/reinstalling systemd services...${NC}"
    
    # Try to install services using passwordless sudo
    INSTALLED=false
    
    # Use the PASSWORDLESS_SUDO variable set earlier
    if [ "$PASSWORDLESS_SUDO" = "true" ]; then
        # Passwordless sudo is available, proceed with installation
        echo "  Stopping running services..."
        sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "sudo -n systemctl stop ovbuddy ovbuddy-web ovbuddy-wifi 2>/dev/null || true" 2>/dev/null
        
        echo "  Waiting for services to stop..."
        sleep 3
        
        echo "  Installing all services..."
        echo "    - ovbuddy.service (display)"
        echo "    - ovbuddy-web.service (web interface)"
        echo "    - ovbuddy-wifi.service (WiFi monitor, if enabled)"
        echo "    - fix-bonjour.service (avahi-daemon fix)"
        
        # Some systems are slow to stop/start services or install WiFi deps; keep this generous.
        if $TIMEOUT_CMD 300 sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "sudo -n bash ${REMOTE_DIR}/install-all-services.sh" 2>&1; then
            INSTALLED=true
            echo -e "${GREEN}  ✓ All services installed successfully${NC}"
        else
            echo -e "${YELLOW}  ⚠ Service installation failed or timed out${NC}"
        fi
    else
        echo -e "${YELLOW}  ⚠ Passwordless sudo not available${NC}"
        echo -e "${YELLOW}     Attempting installation with password prompt...${NC}"
        
        # Try with password (will prompt user)
        echo ""
        echo "You may be prompted for the Pi's sudo password..."
        if sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "sudo bash ${REMOTE_DIR}/install-all-services.sh" 2>&1; then
            INSTALLED=true
            echo -e "${GREEN}  ✓ All services installed successfully${NC}"
        else
            echo -e "${YELLOW}  ⚠ Service installation failed${NC}"
        fi
    fi
    
    if [ "$INSTALLED" != true ]; then
        echo ""
        echo -e "${YELLOW}Service installation incomplete. To install manually:${NC}"
        echo -e "${YELLOW}  1. SSH to the Pi: ssh ${PI_USER}@${PI_SSH_HOST}${NC}"
        echo -e "${YELLOW}  2. Run: cd ${REMOTE_DIR} && sudo ./install-all-services.sh${NC}"
        echo ""
        echo -e "${YELLOW}Or enable passwordless sudo for automatic installation:${NC}"
        echo -e "${YELLOW}  cd /Users/mik/Development/Pi/OVBuddy/scripts${NC}"
        echo -e "${YELLOW}  ./setup-passwordless-sudo.sh${NC}"
    else
        echo -e "${GREEN}  ✓ Services installed and configured:${NC}"
        echo -e "${GREEN}    - ovbuddy.service (display)${NC}"
        echo -e "${GREEN}    - ovbuddy-web.service (web interface)${NC}"
        echo -e "${GREEN}    - ovbuddy-wifi.service (WiFi monitor)${NC}"
        echo -e "${GREEN}    - fix-bonjour.service (avahi-daemon)${NC}"
    fi
fi

echo ""
echo -e "${GREEN}Deployment complete!${NC}"

# Reboot if requested
if [ "$REBOOT_AFTER" = true ]; then
    echo ""
    echo -e "${YELLOW}Rebooting device...${NC}"
    
    # Trigger reboot
    sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "sudo -n reboot" 2>/dev/null || {
        echo -e "${RED}Error: Could not reboot device (requires passwordless sudo)${NC}"
        exit 1
    }
    
    echo "  Device is rebooting..."
    echo "  Waiting for device to shut down..."
    sleep 10
    
    # Wait for device to come back online
    echo "  Waiting for device to come back online..."
    MAX_WAIT=120  # Maximum wait time in seconds
    ELAPSED=0
    PING_INTERVAL=5
    
    while [ $ELAPSED -lt $MAX_WAIT ]; do
        if ping -c 1 -W 1 "$PI_SSH_HOST" > /dev/null 2>&1; then
            echo -e "${GREEN}  ✓ Device is responding to ping${NC}"
            # Wait a bit more for SSH to be ready
            sleep 5
            
            # Try to connect via SSH
            if sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "echo 'SSH ready'" > /dev/null 2>&1; then
                echo -e "${GREEN}  ✓ SSH is ready${NC}"
                break
            fi
        fi
        
        echo "  Still waiting... (${ELAPSED}s/${MAX_WAIT}s)"
        sleep $PING_INTERVAL
        ELAPSED=$((ELAPSED + PING_INTERVAL))
    done
    
    if [ $ELAPSED -ge $MAX_WAIT ]; then
        echo -e "${RED}Error: Device did not come back online within ${MAX_WAIT} seconds${NC}"
        exit 1
    fi
    
    # Give services a bit more time to start
    echo "  Waiting for services to start..."
    sleep 10
    
    # Check service status
    echo ""
    echo -e "${YELLOW}=== Checking Service Status ===${NC}"
    echo ""
    
    # Check ovbuddy-web service
    echo "Checking ovbuddy-web service..."
    WEB_STATUS=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "systemctl is-active ovbuddy-web 2>/dev/null || echo 'inactive'" 2>/dev/null)
    if [ "$WEB_STATUS" == "active" ]; then
        echo -e "${GREEN}  ✓ ovbuddy-web is running${NC}"
    else
        echo -e "${RED}  ✗ ovbuddy-web is NOT running (status: $WEB_STATUS)${NC}"
        echo "  Recent logs:"
        sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "journalctl -u ovbuddy-web -n 10 --no-pager" 2>/dev/null || true
    fi
    
    echo ""
    
    # Check ovbuddy service
    echo "Checking ovbuddy service..."
    OVBUDDY_STATUS=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "systemctl is-active ovbuddy 2>/dev/null || echo 'inactive'" 2>/dev/null)
    if [ "$OVBUDDY_STATUS" == "active" ]; then
        echo -e "${GREEN}  ✓ ovbuddy is running${NC}"
    else
        echo -e "${RED}  ✗ ovbuddy is NOT running (status: $OVBUDDY_STATUS)${NC}"
        echo "  Recent logs:"
        sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "journalctl -u ovbuddy -n 10 --no-pager" 2>/dev/null || true
    fi
    
    echo ""
    
    # Summary
    if [ "$WEB_STATUS" == "active" ] && [ "$OVBUDDY_STATUS" == "active" ]; then
        echo -e "${GREEN}=== All services are running! ===${NC}"
    else
        echo -e "${YELLOW}=== Some services are not running ===${NC}"
        echo ""
        echo "To troubleshoot:"
        echo "  ssh ${PI_USER}@${PI_SSH_HOST}"
        if [ "$WEB_STATUS" != "active" ]; then
            echo "  sudo journalctl -u ovbuddy-web -f"
        fi
        if [ "$OVBUDDY_STATUS" != "active" ]; then
            echo "  sudo journalctl -u ovbuddy -f"
        fi
    fi
else
    # Original completion message when not rebooting
    echo ""
    if [ "$INSTALLED" != true ]; then
        echo "To install as a systemd service (runs on startup):"
        echo "  ssh ${PI_USER}@${PI_SSH_HOST}"
        echo "  cd ${REMOTE_DIR}"
        echo "  sudo ./install-service.sh"
        echo ""
    fi
    echo "Or to run manually:"
    echo "  ssh ${PI_USER}@${PI_SSH_HOST}"
    echo "  cd ${REMOTE_DIR}"
    echo "  python3 ovbuddy.py"
fi
