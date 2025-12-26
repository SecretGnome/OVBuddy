# Automatic Service Installation

## Overview

All OVBuddy services are now automatically installed as part of the deployment process. No manual steps required after running `./deploy.sh`.

## Services Installed Automatically

When you run `./deploy.sh`, the following services are installed and configured:

1. **fix-bonjour.service** - Ensures avahi-daemon starts reliably on boot
2. **ovbuddy-wifi.service** - WiFi monitor with AP fallback (if enabled)
3. **ovbuddy.service** - Main display service
4. **ovbuddy-web.service** - Web interface

## How It Works

### Deployment Process

```bash
cd /Users/mik/Development/Pi/OVBuddy/scripts
./deploy.sh
```

The deploy script:
1. Copies all files from `dist/` to `/home/pi/ovbuddy/`
2. Makes scripts executable
3. Installs Python dependencies (if needed)
4. Fixes Bonjour/mDNS configuration
5. **Automatically installs all systemd services**
6. Starts all services

### Service Installation

The `install-all-services.sh` script:
1. Stops any running services
2. Installs service files to `/etc/systemd/system/`
3. Copies `fix-bonjour-persistent.sh` to `/usr/local/bin/`
4. Installs WiFi dependencies (hostapd, dnsmasq) if needed
5. Reloads systemd daemon
6. Enables services to start on boot
7. Starts all services in the correct order

### Boot Order

Services start in this order on boot:

```
1. network-online.target
2. dbus.service
3. systemd-resolved.service
4. fix-bonjour.service
   ├─ Cleans /etc/hosts
   ├─ Unmasks avahi-daemon
   ├─ Enables avahi-daemon
   └─ Starts avahi-daemon
5. avahi-daemon.service
6. ovbuddy-wifi.service (waits 5 seconds)
7. ovbuddy.service
8. ovbuddy-web.service
```

## No Manual Steps Required

### Before (Old Way)
```bash
# Deploy files
./deploy.sh

# SSH to Pi
ssh pi@192.168.1.167

# Manually install services
cd /home/pi/ovbuddy
sudo ./install-service.sh

# Exit and reboot
sudo reboot
```

### After (New Way)
```bash
# Deploy files (services installed automatically)
./deploy.sh

# That's it! Services are already installed and running.
```

## Passwordless Sudo

For automatic installation to work, passwordless sudo should be configured:

```bash
cd /Users/mik/Development/Pi/OVBuddy/scripts
./setup-passwordless-sudo.sh
```

This is a **one-time setup** that enables:
- Automatic service installation during deployment
- Force AP mode functionality
- Bonjour/mDNS fixes without manual intervention

### Without Passwordless Sudo

If passwordless sudo is not configured, the deploy script will:
1. Attempt to install services with password prompt
2. Ask you to enter the Pi's password during deployment
3. Still install all services automatically

## Verification

After deployment, verify all services are running:

```bash
ssh pi@192.168.1.167 'sudo systemctl status fix-bonjour ovbuddy-wifi ovbuddy ovbuddy-web --no-pager'
```

All should show `active (running)`.

## Service Management

### View Status
```bash
# All services
ssh pi@ovbuddy.local 'sudo systemctl status fix-bonjour ovbuddy-wifi ovbuddy ovbuddy-web'

# Individual service
ssh pi@ovbuddy.local 'sudo systemctl status ovbuddy'
```

### View Logs
```bash
# All services
ssh pi@ovbuddy.local 'sudo journalctl -u fix-bonjour -u ovbuddy-wifi -u ovbuddy -u ovbuddy-web -f'

# Individual service
ssh pi@ovbuddy.local 'sudo journalctl -u ovbuddy -f'
```

### Restart Services
```bash
# All services
ssh pi@ovbuddy.local 'sudo systemctl restart fix-bonjour ovbuddy-wifi ovbuddy ovbuddy-web'

# Individual service
ssh pi@ovbuddy.local 'sudo systemctl restart ovbuddy'
```

### Stop Services
```bash
# All services
ssh pi@ovbuddy.local 'sudo systemctl stop ovbuddy ovbuddy-web ovbuddy-wifi'

# Individual service
ssh pi@ovbuddy.local 'sudo systemctl stop ovbuddy'
```

## Deployment Options

### Full Deployment (Default)
```bash
./deploy.sh
```
- Deploys all files
- Installs all services
- Starts all services

### Deploy with Reboot
```bash
./deploy.sh -reboot
```
- Deploys all files
- Installs all services
- Reboots the device
- Waits for boot
- Checks service status

### Deploy Main File Only
```bash
./deploy.sh -main
```
- Deploys only `ovbuddy.py`
- Does not install services
- Useful for quick code updates

## GitHub Deployment

When deploying via GitHub (future feature), the same automatic installation will occur:

```bash
# On the Pi
cd /home/pi/ovbuddy
git pull
sudo ./install-all-services.sh
```

The `install-all-services.sh` script can be run independently and will:
- Install all services
- Configure dependencies
- Start everything in the correct order

## Troubleshooting

### Services Not Installing

**Check if passwordless sudo is configured:**
```bash
ssh pi@192.168.1.167 'sudo -n echo "test"'
```

If it asks for password:
```bash
cd scripts
./setup-passwordless-sudo.sh
```

**Check deploy script output:**
Look for:
- `✓ All services installed successfully`
- `✓ fix-bonjour service enabled and started`
- `✓ ovbuddy-wifi service enabled and started`

### Services Not Starting

**Check service status:**
```bash
ssh pi@ovbuddy.local 'sudo systemctl status fix-bonjour ovbuddy-wifi ovbuddy ovbuddy-web'
```

**Check logs:**
```bash
ssh pi@ovbuddy.local 'sudo journalctl -b'
```

**Manually reinstall:**
```bash
ssh pi@ovbuddy.local
cd /home/pi/ovbuddy
sudo ./install-all-services.sh
```

### Avahi-Daemon Not Starting

**Check if fix-bonjour service is running:**
```bash
ssh pi@ovbuddy.local 'sudo systemctl status fix-bonjour'
```

**Check avahi-daemon status:**
```bash
ssh pi@ovbuddy.local 'sudo systemctl status avahi-daemon'
```

**Check if masked:**
```bash
ssh pi@ovbuddy.local 'sudo systemctl is-masked avahi-daemon'
```

If masked:
```bash
ssh pi@ovbuddy.local 'sudo systemctl unmask avahi-daemon'
ssh pi@ovbuddy.local 'sudo systemctl enable avahi-daemon'
ssh pi@ovbuddy.local 'sudo systemctl start avahi-daemon'
```

## Files Modified

### Deployment Scripts
- `scripts/deploy.sh` - Now calls `install-all-services.sh` automatically
- `dist/install-service.sh` - Now a wrapper for `install-all-services.sh`
- `dist/install-all-services.sh` - Enhanced to install all services including fix-bonjour

### Service Files
- `dist/fix-bonjour.service` - Better dependencies and restart policy
- `dist/ovbuddy-wifi.service` - Dependencies and startup delay
- `dist/ovbuddy.service` - No changes
- `dist/ovbuddy-web.service` - No changes

### Scripts
- `dist/fix-bonjour-persistent.sh` - Ensures avahi-daemon starts
- `dist/wifi-monitor.py` - Checks for force-AP flag on boot
- `dist/force-ap-mode.sh` - Creates flag file instead of clearing WiFi

## Summary

✅ **All services are now installed automatically during deployment**  
✅ **No manual SSH steps required**  
✅ **Services start in the correct order on boot**  
✅ **Avahi-daemon starts reliably**  
✅ **Force AP mode works correctly**  
✅ **Works with or without passwordless sudo**  

Just run `./deploy.sh` and everything is configured!

