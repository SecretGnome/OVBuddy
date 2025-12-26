# WiFi Access Point Fallback - Implementation Summary

## Overview

This document summarizes the implementation of the WiFi Access Point (AP) fallback feature for OVBuddy. When the Raspberry Pi cannot connect to a configured WiFi network, it will automatically create its own access point, allowing direct connection for configuration.

## Files Created/Modified

### New Files

1. **`dist/wifi-monitor.py`** - Main WiFi monitoring script
   - Monitors WiFi connectivity every 30 seconds
   - Switches to AP mode after 2 minutes of disconnection
   - Automatically reconnects when WiFi becomes available
   - Configurable via `config.json`

2. **`dist/ovbuddy-wifi.service`** - Systemd service for WiFi monitor
   - Runs as root (required for network configuration)
   - Starts before ovbuddy services
   - Auto-restarts on failure

3. **`dist/install-wifi-monitor.sh`** - Installation script
   - Installs required packages (hostapd, dnsmasq)
   - Copies files to installation directory
   - Configures systemd service
   - Updates config.json with default AP settings

4. **`scripts/install-wifi-monitor.sh`** - Wrapper script
   - Allows installation from scripts directory

5. **`WIFI_AP_FALLBACK.md`** - Comprehensive documentation
   - Installation instructions
   - Configuration guide
   - Troubleshooting section
   - Security considerations

6. **`WIFI_AP_IMPLEMENTATION.md`** - This file
   - Implementation summary
   - Technical details

### Modified Files

1. **`dist/config.json`**
   - Added `ap_fallback_enabled`: Enable/disable AP fallback
   - Added `ap_ssid`: Access point SSID (default: "OVBuddy")
   - Added `ap_password`: Access point password (empty = open network)

2. **`dist/ovbuddy.py`**
   - Added AP configuration to `DEFAULT_CONFIG`
   - Added global variables: `AP_FALLBACK_ENABLED`, `AP_SSID`, `AP_PASSWORD`
   - Updated `load_config()` to load AP settings
   - Updated `save_config()` to save AP settings
   - Updated `get_config_dict()` to return AP settings
   - Updated `update_config()` to handle AP settings

3. **`dist/templates/index.html`**
   - Added "Enable WiFi Access Point Fallback" checkbox
   - Added "Access Point Name (SSID)" input field
   - Added "Access Point Password" input field
   - Added help text for each field

4. **`dist/static/js/app.js`**
   - Updated `loadConfiguration()` to load AP settings
   - Updated `saveConfiguration()` to save AP settings

5. **`README.md`**
   - Added AP fallback to features list
   - Added reference to WIFI_AP_FALLBACK.md
   - Added troubleshooting section for WiFi issues
   - Added WiFi monitor service to service management section

## Technical Details

### WiFi Monitor Operation

#### Client Mode (Normal Operation)
1. Checks WiFi connectivity every 30 seconds
2. Verifies interface has IP address
3. Tests connection to configured network
4. Optional ping test for internet connectivity

#### Switching to AP Mode
1. Triggered after 2 minutes of disconnection
2. Stops wpa_supplicant and dhcpcd services
3. Configures wlan0 with static IP (192.168.4.1/24)
4. Creates hostapd configuration (WPA2 or open)
5. Creates dnsmasq configuration (DHCP + DNS)
6. Starts hostapd and dnsmasq

#### AP Mode Operation
1. Provides WiFi access point
2. DHCP server assigns IPs (192.168.4.2-20)
3. DNS resolves ovbuddy.local to 192.168.4.1
4. Scans for configured networks every 60 seconds
5. Automatically switches back when WiFi is available

#### Switching Back to Client Mode
1. Triggered when configured network is detected
2. Stops hostapd and dnsmasq
3. Restarts wpa_supplicant and dhcpcd
4. Triggers network reconnection
5. Verifies connection after 5 seconds

### Network Configuration

#### Access Point Settings
- **IP Address**: 192.168.4.1/24
- **DHCP Range**: 192.168.4.2 - 192.168.4.20
- **Channel**: 6 (2.4 GHz)
- **Security**: WPA2 (if password set) or Open
- **DNS**: Resolves ovbuddy.local to 192.168.4.1

#### Timing Parameters
- `CHECK_INTERVAL`: 30 seconds (client mode)
- `DISCONNECT_THRESHOLD`: 120 seconds (before AP mode)
- `AP_CHECK_INTERVAL`: 60 seconds (AP mode scans)

### Security Considerations

#### Open Network Mode
- No password required
- Anyone can connect
- Suitable for initial setup only
- Should be secured after configuration

#### WPA2 Mode
- Password-protected access point
- Standard WPA2-PSK encryption
- Recommended for production use

#### Network Isolation
- AP mode does not route to internet
- Only local services accessible
- No bridge between AP clients and other networks

### Dependencies

#### Required Packages
- **hostapd**: Creates WiFi access point
- **dnsmasq**: Provides DHCP and DNS services

#### Python Requirements
- Standard library only (no additional pip packages)
- subprocess, json, os, sys, signal, logging, time, pathlib

### Service Integration

#### Service Order
1. `network.target` - Basic networking
2. `ovbuddy-wifi.service` - WiFi monitoring (Before ovbuddy services)
3. `ovbuddy-web.service` - Web interface
4. `ovbuddy.service` - Display service

#### Service Dependencies
- WiFi monitor starts before OVBuddy services
- Ensures network is available before services start
- Web interface remains accessible in AP mode

## Configuration

### Default Configuration

```json
{
  "ap_fallback_enabled": true,
  "ap_ssid": "OVBuddy",
  "ap_password": ""
}
```

### Configuration via Web Interface

1. Navigate to web interface
2. Scroll to "Access Point Settings"
3. Toggle "Enable WiFi Access Point Fallback"
4. Set SSID and password
5. Save configuration
6. Restart WiFi monitor service

### Configuration via config.json

Edit `/home/pi/ovbuddy/config.json`:

```json
{
  "ap_fallback_enabled": true,
  "ap_ssid": "MyCustomSSID",
  "ap_password": "MySecurePassword"
}
```

Then restart the service:
```bash
sudo systemctl restart ovbuddy-wifi
```

## Installation

### Automatic Installation (Recommended)

The WiFi monitor is **automatically installed** as part of the standard OVBuddy deployment:

**Via deployment script:**
```bash
cd scripts
./deploy.sh
```

**Or manually on the Pi:**
```bash
cd /home/pi/ovbuddy
sudo ./install-service.sh
```

The unified installer (`install-all-services.sh`) will:
1. Detect if WiFi monitor files are present
2. Check if AP fallback is enabled in config.json
3. Install required packages (`hostapd` and `dnsmasq`) if needed
4. Install and start all services (ovbuddy, ovbuddy-web, ovbuddy-wifi)

**Integration Points:**
- `scripts/deploy.sh` - Calls `install-service.sh` during deployment
- `dist/install-service.sh` - Wrapper that calls `install-all-services.sh`
- `dist/install-all-services.sh` - Unified installer for all services
- `dist/ovbuddy.py` - Auto-update calls `install-service.sh` after updates

### Manual Installation (Advanced)

If you need to install only the WiFi monitor:

1. Install packages:
   ```bash
   sudo apt-get update
   sudo apt-get install -y hostapd dnsmasq
   ```

2. Disable services (managed by wifi-monitor.py):
   ```bash
   sudo systemctl stop hostapd dnsmasq
   sudo systemctl disable hostapd dnsmasq
   ```

3. Copy files:
   ```bash
   sudo cp wifi-monitor.py /home/pi/ovbuddy/
   sudo chmod +x /home/pi/ovbuddy/wifi-monitor.py
   sudo cp ovbuddy-wifi.service /etc/systemd/system/
   ```

4. Enable service:
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable ovbuddy-wifi
   sudo systemctl start ovbuddy-wifi
   ```

## Testing

### Test AP Fallback

1. Disconnect from WiFi:
   ```bash
   sudo wpa_cli -i wlan0 disconnect
   ```

2. Wait 2 minutes

3. Check for AP:
   ```bash
   # On another device, scan for "OVBuddy" network
   ```

4. Connect and access: `http://192.168.4.1:8080`

### Test Auto-Reconnect

1. While in AP mode, enable WiFi on router

2. Wait up to 60 seconds

3. Monitor logs:
   ```bash
   sudo journalctl -u ovbuddy-wifi -f
   ```

4. Should see "Configured WiFi network detected" message

5. Should automatically switch back to client mode

## Monitoring

### Service Status

```bash
sudo systemctl status ovbuddy-wifi
```

### Real-time Logs

```bash
sudo journalctl -u ovbuddy-wifi -f
```

### Log File

```bash
cat /var/log/ovbuddy-wifi.log
```

### Check Current Mode

```bash
# Check interface mode
sudo iwconfig wlan0

# Client mode: Mode:Managed
# AP mode: Mode:Master
```

### Check IP Address

```bash
ip addr show wlan0

# Client mode: Dynamic IP (e.g., 192.168.1.x)
# AP mode: Static IP (192.168.4.1)
```

## Troubleshooting

See [WIFI_AP_FALLBACK.md](WIFI_AP_FALLBACK.md) for comprehensive troubleshooting guide.

### Common Issues

1. **Service won't start**
   - Check for conflicting services (hostapd, dnsmasq)
   - Verify files are in correct locations
   - Check logs for errors

2. **AP not visible**
   - Verify hostapd is running
   - Check wlan0 is in Master mode
   - Ensure no other process is using wlan0

3. **Can't connect to AP**
   - Verify password is correct
   - Check hostapd configuration
   - Ensure dnsmasq is running

4. **Not reconnecting to WiFi**
   - Verify configured network is in range
   - Check wpa_supplicant configuration
   - Ensure wpa_supplicant service is enabled

## Future Enhancements

Possible improvements:

1. **Multi-network support**: Try multiple configured networks before AP mode
2. **Captive portal**: Redirect all traffic to configuration page
3. **Network quality monitoring**: Switch networks based on signal strength
4. **Mobile app**: Dedicated app for configuration
5. **Bluetooth fallback**: Alternative connection method
6. **Email notifications**: Alert when switching to AP mode
7. **Scheduled AP mode**: Enable AP at specific times
8. **Guest network**: Separate network for guests

## Conclusion

The WiFi Access Point fallback feature provides a robust solution for network connectivity issues. It ensures the device remains accessible even when the configured WiFi network is unavailable, making initial setup and troubleshooting much easier.

The implementation is:
- **Automatic**: No manual intervention required
- **Configurable**: All settings adjustable via web interface
- **Reliable**: Automatic recovery when WiFi returns
- **Secure**: Optional password protection
- **Well-documented**: Comprehensive documentation and troubleshooting

For detailed usage instructions, see [WIFI_AP_FALLBACK.md](WIFI_AP_FALLBACK.md).

