#!/bin/bash

# Deployment script for ovbuddy to Raspberry Pi
# Reads credentials from .env file
# Deploys all files from the dist/ folder
# Usage: ./scripts/deploy.sh [-main] [-reboot]
#   -main   : deploy only ovbuddy.py
#   -reboot : reboot device after deployment and check service status

# Change to project root directory (parent of scripts/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

set -e  # Exit on error

# Check for arguments
DEPLOY_MAIN_ONLY=false
REBOOT_AFTER=false
for arg in "$@"; do
    if [ "$arg" == "-main" ]; then
        DEPLOY_MAIN_ONLY=true
    elif [ "$arg" == "-reboot" ]; then
        REBOOT_AFTER=true
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

# Load environment variables from .env file
set -a
source .env
set +a

# Validate required variables
if [ -z "$PI_HOST" ] || [ -z "$PI_USER" ] || [ -z "$PI_PASSWORD" ]; then
    echo -e "${RED}Error: PI_HOST, PI_USER, and PI_PASSWORD must be set in .env file${NC}"
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

# Check if dist folder exists
if [ ! -d "dist" ]; then
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

echo -e "${YELLOW}Deploying ovbuddy to ${PI_USER}@${PI_SSH_HOST}:${REMOTE_DIR}${NC}"

# Create remote directory if it doesn't exist
echo "Creating remote directory..."
sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "mkdir -p ${REMOTE_DIR}"

# Copy files to Raspberry Pi
if [ "$DEPLOY_MAIN_ONLY" == true ]; then
    echo "Deploying only ovbuddy.py..."
    if [ ! -f "dist/ovbuddy.py" ]; then
        echo -e "${RED}Error: dist/ovbuddy.py not found!${NC}"
        exit 1
    fi
    echo "  → ovbuddy.py"
    sshpass -p "$PI_PASSWORD" scp $SCP_OPTS "dist/ovbuddy.py" "${PI_USER}@${PI_SSH_HOST}:${REMOTE_DIR}/"
    echo -e "${GREEN}ovbuddy.py deployed successfully!${NC}"
    echo ""
    echo "Note: Only ovbuddy.py was deployed. To deploy all files, run without -main argument."
else
    echo "Copying files from dist/ folder..."
    
    # Deploy all files from dist folder
    for file in dist/*; do
        if [ -f "$file" ]; then
            filename=$(basename "$file")
            echo "  → $filename"
            sshpass -p "$PI_PASSWORD" scp $SCP_OPTS "$file" "${PI_USER}@${PI_SSH_HOST}:${REMOTE_DIR}/"
        fi
    done
    
    # Deploy templates and static directories if they exist
    if [ -d "dist/templates" ]; then
        echo "  → templates/ (directory)"
        sshpass -p "$PI_PASSWORD" scp $SCP_OPTS -r "dist/templates" "${PI_USER}@${PI_SSH_HOST}:${REMOTE_DIR}/"
    fi
    if [ -d "dist/static" ]; then
        echo "  → static/ (directory)"
        sshpass -p "$PI_PASSWORD" scp $SCP_OPTS -r "dist/static" "${PI_USER}@${PI_SSH_HOST}:${REMOTE_DIR}/"
    fi

    # Make scripts executable
    echo ""
    echo "Making scripts executable..."
    sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "cd ${REMOTE_DIR} && chmod +x *.sh 2>/dev/null || true"
    
    # Install Python dependencies if requirements.txt exists
    # Only install if this is a fresh installation (no existing ovbuddy folder) or if explicitly requested
    if [ -f "dist/requirements.txt" ]; then
        # Check if this is a fresh installation
        IS_FRESH_INSTALL=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "[ ! -d ${REMOTE_DIR} ] && echo 'true' || echo 'false'")
        
        if [ "$IS_FRESH_INSTALL" = "true" ]; then
            echo ""
            echo -e "${YELLOW}Fresh installation detected - installing Python dependencies...${NC}"
            INSTALL_DEPS=true
        else
            # Check if dependencies are already installed
            FLASK_INSTALLED=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "python3 -c 'import flask' 2>/dev/null && echo 'true' || echo 'false'")
            PYQRCODE_INSTALLED=$(sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "python3 -c 'import pyqrcode' 2>/dev/null && echo 'true' || echo 'false'")
            
            if [ "$FLASK_INSTALLED" = "false" ] || [ "$PYQRCODE_INSTALLED" = "false" ]; then
                echo ""
                echo -e "${YELLOW}Missing dependencies detected - installing Python dependencies...${NC}"
                INSTALL_DEPS=true
            else
                echo ""
                echo -e "${GREEN}Python dependencies already installed, skipping...${NC}"
                INSTALL_DEPS=false
            fi
        fi
        
        if [ "$INSTALL_DEPS" = "true" ]; then
            # Install Flask (required for web server)
            if [ "$FLASK_INSTALLED" != "true" ]; then
                echo -e "${YELLOW}  Installing Flask (required)...${NC}"
                sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "cd ${REMOTE_DIR} && pip3 install --user flask" || {
                    echo -e "${YELLOW}  --user installation failed, trying with --break-system-packages...${NC}"
                    sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "cd ${REMOTE_DIR} && pip3 install --break-system-packages flask"
                }
            fi
            
            # Install pyqrcode and pypng (required for QR code display)
            if [ "$PYQRCODE_INSTALLED" != "true" ]; then
                echo -e "${YELLOW}  Installing pyqrcode and pypng (for QR code)...${NC}"
                sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "cd ${REMOTE_DIR} && pip3 install --user pyqrcode pypng" || {
                    echo -e "${YELLOW}  --user installation failed, trying with --break-system-packages...${NC}"
                    sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "cd ${REMOTE_DIR} && pip3 install --break-system-packages pyqrcode pypng"
                }
            fi
            
            # Skip zeroconf installation - it takes too long to build on Raspberry Pi
            # Users can install it manually later if they want Bonjour support
            echo -e "${YELLOW}  Skipping zeroconf (optional, takes 15+ minutes to build on Pi)${NC}"
            echo -e "${YELLOW}  Web server will work without it. To install later: pip3 install --break-system-packages zeroconf${NC}"
        fi
    fi
    
fi

# Fix Bonjour/mDNS setup (always run, regardless of PI_HOST format or deployment type)
echo ""
echo -e "${YELLOW}Fixing Bonjour/mDNS setup...${NC}"
# Remove .local entries from /etc/hosts that interfere with mDNS
# Use timeout to prevent hanging if sudo requires password
timeout 10 sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
    sudo -n sed -i '/\.local/d' /etc/hosts 2>/dev/null || true
    echo '✓ Removed .local entries from /etc/hosts'
" 2>/dev/null || {
    echo -e "${YELLOW}  ⚠ Could not remove .local entries (may require passwordless sudo or timed out)${NC}"
}

# Ensure avahi-daemon is enabled and running
# Use timeout to prevent hanging if sudo requires password
timeout 10 sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
    sudo -n systemctl enable avahi-daemon 2>/dev/null && \
    sudo -n systemctl start avahi-daemon 2>/dev/null && \
    echo '✓ avahi-daemon enabled and started'
" 2>/dev/null || {
    echo -e "${YELLOW}  ⚠ Could not enable/start avahi-daemon (may require passwordless sudo or timed out)${NC}"
}

# Restart avahi-daemon to ensure mDNS is working (non-blocking)
# Use try-restart which is non-blocking, run in background with short timeout
(timeout 10 sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
    sudo -n systemctl try-restart avahi-daemon 2>/dev/null || true
    echo '✓ avahi-daemon restart attempted'
" 2>/dev/null &)
# Wait max 3 seconds for the background process, then continue
sleep 3
wait 2>/dev/null || true

# Install persistent Bonjour fix (runs on boot)
if [ -f "dist/fix-bonjour.service" ]; then
    echo ""
    echo -e "${YELLOW}Installing persistent Bonjour fix (runs on boot)...${NC}"
    
    # Install service and timer using non-blocking commands with timeouts
    INSTALLED=false
    timeout 10 sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
        cd ${REMOTE_DIR} && \
        sudo -n cp fix-bonjour.service /etc/systemd/system/ 2>/dev/null && \
        echo '✓ Copied service file'
    " 2>/dev/null && INSTALLED=true || {
        echo -e "${YELLOW}  ⚠ Could not copy service file (may require passwordless sudo or timed out)${NC}"
    }
    
    # Copy timer if it exists
    if [ "$INSTALLED" = true ] && [ -f "dist/fix-bonjour.timer" ]; then
        timeout 10 sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
            cd ${REMOTE_DIR} && \
            sudo -n cp fix-bonjour.timer /etc/systemd/system/ 2>/dev/null && \
            echo '✓ Copied timer file'
        " 2>/dev/null || {
            echo -e "${YELLOW}  ⚠ Could not copy timer file (timed out)${NC}"
        }
    fi
    
    # Reload systemd and enable services (non-blocking with timeout)
    if [ "$INSTALLED" = true ]; then
        timeout 15 sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
            sudo -n systemctl daemon-reload 2>/dev/null && \
            sudo -n systemctl enable fix-bonjour.service 2>/dev/null && \
            sudo -n systemctl start fix-bonjour.service 2>/dev/null && \
            echo '✓ Service installed and started'
        " 2>/dev/null || {
            echo -e "${YELLOW}  ⚠ Could not enable/start service (may require passwordless sudo or timed out)${NC}"
        }
        
        # Enable and start timer if it exists
        if [ -f "dist/fix-bonjour.timer" ]; then
            timeout 15 sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "
                sudo -n systemctl enable fix-bonjour.timer 2>/dev/null && \
                sudo -n systemctl start fix-bonjour.timer 2>/dev/null && \
                echo '✓ Timer installed and started'
            " 2>/dev/null || {
                echo -e "${YELLOW}  ⚠ Could not enable/start timer (timed out)${NC}"
            }
        fi
        
        if [ "$INSTALLED" = true ]; then
            echo -e "${GREEN}  ✓ Persistent Bonjour fix installed${NC}"
        fi
    else
        echo -e "${YELLOW}  ⚠ Installation skipped (requires passwordless sudo)${NC}"
        echo -e "${YELLOW}  To enable passwordless sudo and install, run on the Pi:${NC}"
        echo -e "${YELLOW}    echo '${PI_USER} ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/${PI_USER}${NC}"
        echo -e "${YELLOW}  Then run: cd ${REMOTE_DIR} && sudo ./install-fix-bonjour.sh${NC}"
    fi
fi

echo -e "${GREEN}  ✓ Bonjour/mDNS fix applied${NC}"
echo -e "${YELLOW}  Note: You may need to flush DNS cache on your Mac:${NC}"
echo -e "${YELLOW}    sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder${NC}"

# Install/reinstall systemd services (ovbuddy and ovbuddy-web)
if [ -f "dist/install-service.sh" ]; then
    echo ""
    echo -e "${YELLOW}Installing/reinstalling systemd services...${NC}"
    
    # Try to install services using passwordless sudo
    INSTALLED=false
    
    # Check if passwordless sudo is available (test with a simple command)
    if timeout 5 sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "sudo -n echo 'test' > /dev/null 2>&1" 2>/dev/null; then
        # Passwordless sudo is available, proceed with installation
        echo "  Checking for running services..."
        timeout 10 sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "sudo -n systemctl stop ovbuddy ovbuddy-web 2>/dev/null || true" 2>/dev/null
        
        echo "  Waiting for services to stop..."
        sleep 3
        
        echo "  Installing services..."
        if timeout 30 sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS "${PI_USER}@${PI_SSH_HOST}" "cd ${REMOTE_DIR} && sudo -n bash install-service.sh" 2>&1; then
            INSTALLED=true
        else
            echo -e "${YELLOW}  ⚠ Service installation failed or timed out${NC}"
        fi
    else
        echo -e "${YELLOW}  ⚠ Passwordless sudo not available, skipping automatic service installation${NC}"
    fi
    
    if [ "$INSTALLED" != true ]; then
        echo -e "${YELLOW}  To enable passwordless sudo and install services automatically, run on the Pi:${NC}"
        echo -e "${YELLOW}    echo '${PI_USER} ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/${PI_USER}${NC}"
        echo -e "${YELLOW}  Then run: cd ${REMOTE_DIR} && sudo ./install-service.sh${NC}"
    fi
    
    if [ "$INSTALLED" = true ]; then
        echo -e "${GREEN}  ✓ Systemd services installed/reinstalled and restarted${NC}"
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
