# WiFi AP Fallback - Integration Summary

## Overview

The WiFi Access Point fallback feature has been fully integrated into the OVBuddy deployment and update system. The WiFi monitor service is now automatically installed and managed alongside the main display and web services.

## Integration Architecture

### Unified Service Installation

All services are now installed through a single unified installer:

```
deploy.sh (deployment)
    └─> install-service.sh (wrapper)
        └─> install-all-services.sh (unified installer)
            ├─> ovbuddy.service
            ├─> ovbuddy-web.service
            └─> ovbuddy-wifi.service (conditional)

ovbuddy.py (auto-update)
    └─> install-service.sh (wrapper)
        └─> install-all-services.sh (unified installer)
            ├─> ovbuddy.service
            ├─> ovbuddy-web.service
            └─> ovbuddy-wifi.service (conditional)
```

### Key Files

#### New Files Created

1. **`dist/install-all-services.sh`** - Unified service installer
   - Installs all OVBuddy services
   - Conditionally installs WiFi monitor based on config
   - Handles dependency installation (hostapd, dnsmasq)
   - Manages service lifecycle (stop, install, enable, start)

2. **`dist/wifi-monitor.py`** - WiFi monitoring script
   - Monitors WiFi connectivity
   - Switches to AP mode when disconnected
   - Auto-reconnects when WiFi available

3. **`dist/ovbuddy-wifi.service`** - Systemd service for WiFi monitor
   - Runs as root (required for network configuration)
   - Starts before ovbuddy services
   - Auto-restarts on failure

#### Modified Files

1. **`dist/install-service.sh`** - Now a wrapper
   - Simplified to call `install-all-services.sh`
   - Maintains backward compatibility
   - Used by both deploy.sh and auto-update

2. **`scripts/deploy.sh`** - Updated deployment
   - Increased timeout for service installation (30s → 60s)
   - Stops ovbuddy-wifi service before installation
   - Reports WiFi monitor installation status

3. **`dist/ovbuddy.py`** - Auto-update integration
   - Checks for ovbuddy-wifi service
   - Restarts WiFi monitor after updates
   - Includes ovbuddy-wifi in service status API

4. **`dist/config.json`** - AP configuration
   - Added `ap_fallback_enabled` (default: true)
   - Added `ap_ssid` (default: "OVBuddy")
   - Added `ap_password` (default: "")

5. **`dist/templates/index.html`** - Web interface
   - Added AP configuration section
   - Enable/disable toggle
   - SSID and password inputs

6. **`dist/static/js/app.js`** - JavaScript updates
   - Load/save AP configuration
   - Form validation

## Installation Flow

### During Deployment (deploy.sh)

1. **File Transfer**
   - All files copied to `/home/pi/ovbuddy`
   - Includes `wifi-monitor.py`, `ovbuddy-wifi.service`, `install-all-services.sh`

2. **Service Installation**
   - Stops all services (ovbuddy, ovbuddy-web, ovbuddy-wifi)
   - Calls `install-service.sh` with passwordless sudo
   - `install-service.sh` calls `install-all-services.sh`

3. **Unified Installer Actions**
   - Checks if WiFi monitor files exist
   - Reads `ap_fallback_enabled` from config.json
   - If enabled:
     - Installs hostapd and dnsmasq
     - Disables hostapd and dnsmasq services
     - Installs ovbuddy-wifi.service
     - Enables and starts the service

### During Auto-Update (ovbuddy.py)

1. **Update Process**
   - Downloads latest version from GitHub
   - Updates all files in `/home/pi/ovbuddy`

2. **Service Reinstallation**
   - Calls `install-service.sh` with sudo
   - `install-service.sh` calls `install-all-services.sh`
   - All services reinstalled and restarted

3. **Fallback Restart**
   - If install-service.sh fails, manually restart services
   - Checks each service (ovbuddy, ovbuddy-web, ovbuddy-wifi)
   - Restarts active services

## Conditional Installation

The WiFi monitor is only installed if **all** of the following are true:

1. `wifi-monitor.py` file exists
2. `ovbuddy-wifi.service` file exists
3. `ap_fallback_enabled` is `true` in config.json

If any condition is false, the WiFi monitor is skipped with a warning message.

## Service Dependencies

### Service Order

```
network.target
    └─> ovbuddy-wifi.service (Before: ovbuddy services)
        ├─> ovbuddy-web.service
        └─> ovbuddy.service
```

### Why This Order?

- **WiFi monitor starts first**: Ensures network is available before other services
- **Web service before display**: Web interface accessible even if display fails
- **All services independent**: Can be stopped/started individually

## Configuration Management

### Default Configuration

```json
{
  "ap_fallback_enabled": true,
  "ap_ssid": "OVBuddy",
  "ap_password": ""
}
```

### Configuration Flow

1. **User changes config** via web interface or config.json
2. **Config saved** to `/home/pi/ovbuddy/config.json`
3. **Service restart** required for changes to take effect
4. **Next deployment** respects the configuration

### Enabling/Disabling

**Via Web Interface:**
1. Navigate to web interface
2. Toggle "Enable WiFi Access Point Fallback"
3. Save configuration
4. Restart WiFi monitor: `sudo systemctl restart ovbuddy-wifi`

**Via config.json:**
1. Edit `/home/pi/ovbuddy/config.json`
2. Set `"ap_fallback_enabled": true` or `false`
3. Run `sudo ./install-service.sh` to apply

**Via Deployment:**
1. Edit `dist/config.json` locally
2. Run `./scripts/deploy.sh`
3. Services automatically reinstalled with new config

## API Integration

### Service Status API

**Endpoint:** `GET /api/services/status`

**Response:**
```json
{
  "ovbuddy": "active",
  "ovbuddy-web": "active",
  "ovbuddy-wifi": "active",
  "avahi-daemon": "active"
}
```

### Service Control API

**Endpoint:** `POST /api/services/<service_name>/<action>`

**Allowed Services:**
- `ovbuddy`
- `ovbuddy-web`
- `ovbuddy-wifi`
- `avahi-daemon`

**Allowed Actions:**
- `start`
- `stop`
- `restart`

## Testing

### Test Deployment

```bash
# Deploy to Raspberry Pi
cd scripts
./deploy.sh

# Check service status
ssh pi@ovbuddy.local
sudo systemctl status ovbuddy-wifi
sudo journalctl -u ovbuddy-wifi -n 50
```

### Test Auto-Update

```bash
# Trigger update via web interface
# Or manually:
ssh pi@ovbuddy.local
cd /home/pi/ovbuddy
sudo ./install-service.sh

# Verify all services running
systemctl status ovbuddy ovbuddy-web ovbuddy-wifi
```

### Test AP Fallback

```bash
# Disconnect from WiFi
sudo wpa_cli -i wlan0 disconnect

# Wait 2 minutes, check logs
sudo journalctl -u ovbuddy-wifi -f

# Should see "Switching to Access Point mode..."
# Connect to "OVBuddy" network
# Access http://192.168.4.1:8080
```

## Troubleshooting

### Service Not Installing

**Symptom:** WiFi monitor not installed during deployment

**Causes:**
1. `ap_fallback_enabled` is `false` in config.json
2. WiFi monitor files missing from dist/
3. Passwordless sudo not configured

**Solution:**
```bash
# Check config
cat /home/pi/ovbuddy/config.json | grep ap_fallback

# Check files
ls -la /home/pi/ovbuddy/wifi-monitor.py
ls -la /home/pi/ovbuddy/ovbuddy-wifi.service

# Setup passwordless sudo
echo 'pi ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/pi

# Reinstall
cd /home/pi/ovbuddy
sudo ./install-service.sh
```

### Service Fails to Start

**Symptom:** `systemctl status ovbuddy-wifi` shows failed

**Causes:**
1. hostapd or dnsmasq not installed
2. Conflicting services running
3. wlan0 interface busy

**Solution:**
```bash
# Check dependencies
dpkg -l | grep hostapd
dpkg -l | grep dnsmasq

# Check for conflicts
systemctl status hostapd
systemctl status dnsmasq

# Disable conflicts
sudo systemctl stop hostapd dnsmasq
sudo systemctl disable hostapd dnsmasq

# Check interface
ip addr show wlan0
sudo lsof | grep wlan0

# Restart service
sudo systemctl restart ovbuddy-wifi
```

### Not Switching to AP Mode

**Symptom:** WiFi disconnected but no AP created

**Causes:**
1. Service not running
2. Disconnect threshold not reached (need 2 minutes)
3. Configuration error

**Solution:**
```bash
# Check service
sudo systemctl status ovbuddy-wifi

# Check logs
sudo journalctl -u ovbuddy-wifi -n 100

# Check config
cat /home/pi/ovbuddy/config.json | grep -A3 ap_

# Manual trigger (for testing)
sudo wpa_cli -i wlan0 disconnect
# Wait 2 minutes
```

## Benefits of Integration

### For Users

1. **Automatic Installation**: No manual steps required
2. **Consistent Updates**: WiFi monitor updated with system
3. **Unified Management**: All services managed together
4. **Configuration Sync**: AP settings persist across updates

### For Developers

1. **Single Installation Path**: One script to maintain
2. **Consistent Behavior**: Same process for deploy and update
3. **Easy Testing**: Deploy script handles everything
4. **Backward Compatible**: Old install-service.sh still works

### For Maintenance

1. **Centralized Logic**: All installation in one place
2. **Conditional Installation**: Only installs when needed
3. **Dependency Management**: Automatic package installation
4. **Service Lifecycle**: Proper stop/start/restart handling

## Future Enhancements

Possible improvements:

1. **Health Checks**: Monitor service health and auto-restart
2. **Configuration Validation**: Validate config before applying
3. **Rollback Support**: Revert to previous version on failure
4. **Installation Hooks**: Pre/post installation scripts
5. **Dependency Checking**: Verify all dependencies before install
6. **Dry Run Mode**: Preview changes without applying
7. **Logging**: Detailed installation logs
8. **Notifications**: Alert on installation success/failure

## Conclusion

The WiFi AP fallback feature is now fully integrated into the OVBuddy deployment and update system. Users benefit from automatic installation and updates, while developers have a single, unified installation path to maintain.

The integration ensures that:
- WiFi monitor is always up-to-date
- Configuration is preserved across updates
- All services are managed consistently
- Installation is automatic and reliable

For detailed usage instructions, see [WIFI_AP_FALLBACK.md](WIFI_AP_FALLBACK.md).
For technical implementation details, see [WIFI_AP_IMPLEMENTATION.md](WIFI_AP_IMPLEMENTATION.md).


