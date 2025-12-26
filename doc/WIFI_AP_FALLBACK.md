# WiFi Access Point Fallback

OVBuddy now includes an automatic WiFi Access Point (AP) fallback feature. When the Raspberry Pi cannot connect to a configured WiFi network, it will automatically create its own access point, allowing you to connect directly to configure WiFi settings.

## Features

- **Automatic Failover**: Switches to AP mode after 2 minutes of WiFi disconnection
- **Auto-Recovery**: Automatically reconnects to WiFi when the network becomes available
- **Configurable**: Customize the AP name (SSID) and password through the web interface
- **Seamless**: Web interface remains accessible at all times

## How It Works

1. **Normal Operation**: The device connects to your configured WiFi network
2. **Connection Lost**: If WiFi is unavailable, the monitor waits 2 minutes
3. **AP Mode**: Creates a WiFi access point with the configured name (default: "OVBuddy")
4. **Direct Access**: Connect to the AP and access the web interface at `http://192.168.4.1:8080`
5. **Reconfiguration**: Use the web interface to configure a new WiFi network
6. **Auto-Reconnect**: When the configured WiFi is detected, automatically switches back to client mode

## Installation

### Prerequisites

The WiFi monitor requires the following packages:
- `hostapd` - For creating the access point
- `dnsmasq` - For DHCP and DNS services

### Automatic Installation

The WiFi monitor is **automatically installed** when you deploy OVBuddy or run the service installer:

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

The installation script will:
1. Detect if WiFi monitor files are present
2. Check if AP fallback is enabled in config.json
3. Install required packages (`hostapd` and `dnsmasq`) if needed
4. Install and start the WiFi monitor service automatically

**Note:** The WiFi monitor is only installed if:
- `wifi-monitor.py` and `ovbuddy-wifi.service` files are present
- `ap_fallback_enabled` is `true` in config.json (default)

## Configuration

### Via Web Interface

1. Open the OVBuddy web interface at `http://ovbuddy.local:8080`
2. Scroll to the "Access Point Settings" section
3. Configure the following options:
   - **Enable WiFi Access Point Fallback**: Toggle the feature on/off
   - **Access Point Name (SSID)**: The name of the WiFi network (default: "OVBuddy")
   - **Access Point Password**: Password for the AP (leave empty for open network)
4. Click "Save Configuration"
5. Restart the WiFi monitor service for changes to take effect

### Via config.json

Edit `/home/pi/ovbuddy/config.json`:

```json
{
  "ap_fallback_enabled": true,
  "ap_ssid": "OVBuddy",
  "ap_password": ""
}
```

- `ap_fallback_enabled`: `true` to enable, `false` to disable
- `ap_ssid`: The WiFi network name (SSID)
- `ap_password`: Password for WPA2 security (empty string = open network)

After editing, restart the service:

```bash
sudo systemctl restart ovbuddy-wifi
```

## Usage

### Manually Forcing AP Mode

You can manually force the device into AP mode using the web interface or command line:

**Via Web Interface:**
1. Open `http://ovbuddy.local:8080`
2. Go to the "WiFi Management" section
3. Click "Force AP Mode" button
4. Confirm the action
5. Device will switch to AP mode in about 2 minutes

**Via Command Line:**
```bash
ssh pi@ovbuddy.local
sudo /home/pi/ovbuddy/force-ap-mode.sh
```

**Via Remote Script:**
```bash
cd scripts
./force-ap-mode.sh  # (if you create a remote wrapper)
```

This is useful for:
- Testing the AP fallback feature
- Troubleshooting WiFi issues
- Reconfiguring WiFi without waiting for disconnection
- Initial setup in areas with no WiFi

### Connecting to the Access Point

When in AP mode (automatic or forced):

1. **Find the Network**: Look for the WiFi network with your configured SSID (default: "OVBuddy")
2. **Connect**: 
   - If you set a password, enter it when prompted
   - If no password is set, it's an open network
3. **Access Web Interface**: Open `http://192.168.4.1:8080` in your browser
4. **Configure WiFi**: Use the WiFi management section to scan and connect to a network

### Checking Current Mode

To see if the device is in AP mode or client mode:

```bash
sudo systemctl status ovbuddy-wifi
```

Or check the logs:

```bash
sudo journalctl -u ovbuddy-wifi -n 50
```

Look for messages like:
- "Starting in client mode (WiFi connected)" - Normal operation
- "Switching to Access Point mode..." - Entering AP mode
- "Switching to WiFi client mode..." - Returning to normal operation

## Service Management

### Check Service Status

```bash
sudo systemctl status ovbuddy-wifi
```

### Start/Stop/Restart Service

```bash
sudo systemctl start ovbuddy-wifi
sudo systemctl stop ovbuddy-wifi
sudo systemctl restart ovbuddy-wifi
```

### Enable/Disable Auto-Start

```bash
sudo systemctl enable ovbuddy-wifi   # Start on boot
sudo systemctl disable ovbuddy-wifi  # Don't start on boot
```

### View Logs

Real-time logs:
```bash
sudo journalctl -u ovbuddy-wifi -f
```

Recent logs:
```bash
sudo journalctl -u ovbuddy-wifi -n 100
```

Log file:
```bash
cat /var/log/ovbuddy-wifi.log
```

## Troubleshooting

### AP Mode Not Activating

1. **Check if service is running**:
   ```bash
   sudo systemctl status ovbuddy-wifi
   ```

2. **Check if feature is enabled** in `config.json`:
   ```bash
   grep -A2 "ap_fallback" /home/pi/ovbuddy/config.json
   ```

3. **Check logs for errors**:
   ```bash
   sudo journalctl -u ovbuddy-wifi -n 50
   ```

### Can't Connect to Access Point

1. **Verify AP is active**:
   ```bash
   sudo iwconfig wlan0
   ```
   Should show "Mode:Master" when in AP mode

2. **Check hostapd is running**:
   ```bash
   ps aux | grep hostapd
   ```

3. **Verify IP address**:
   ```bash
   ip addr show wlan0
   ```
   Should show `192.168.4.1/24`

### Not Reconnecting to WiFi

1. **Check if configured network is in range**:
   ```bash
   sudo iwlist wlan0 scan | grep ESSID
   ```

2. **Manually trigger reconnection**:
   ```bash
   sudo systemctl restart ovbuddy-wifi
   ```

3. **Check wpa_supplicant configuration**:
   ```bash
   sudo wpa_cli -i wlan0 list_networks
   ```

### Service Fails to Start

1. **Check for conflicting services**:
   ```bash
   sudo systemctl status hostapd
   sudo systemctl status dnsmasq
   ```
   These should be disabled (the WiFi monitor manages them)

2. **Disable conflicting services**:
   ```bash
   sudo systemctl stop hostapd
   sudo systemctl stop dnsmasq
   sudo systemctl disable hostapd
   sudo systemctl disable dnsmasq
   ```

3. **Check for other processes using wlan0**:
   ```bash
   sudo lsof | grep wlan0
   ```

## Technical Details

### Timing Parameters

You can adjust these in `wifi-monitor.py`:

- `CHECK_INTERVAL = 30`: Seconds between WiFi checks (client mode)
- `DISCONNECT_THRESHOLD = 120`: Seconds before switching to AP mode
- `AP_CHECK_INTERVAL = 60`: Seconds between WiFi scans (AP mode)

### Network Configuration

When in AP mode:
- **IP Address**: `192.168.4.1/24`
- **DHCP Range**: `192.168.4.2` - `192.168.4.20`
- **Channel**: 6 (2.4 GHz)
- **Security**: WPA2 (if password is set) or Open (if no password)

### Service Dependencies

The WiFi monitor service:
- Starts after `network.target`
- Starts before `ovbuddy.service` and `ovbuddy-web.service`
- Runs as root (required for network configuration)

## Security Considerations

### Open Network Warning

If you configure the AP without a password (`ap_password` is empty):
- **Anyone nearby can connect** to your device
- The web interface will be accessible to anyone who connects
- Consider this only for initial setup or secure environments

### Recommended Security

For better security:
1. Set a strong password for the AP
2. Only enable AP fallback when needed
3. Disable AP fallback once WiFi is properly configured
4. Change the default SSID to something less obvious

### Network Isolation

When in AP mode:
- The device is isolated from the internet
- Only the web interface and local services are accessible
- No routing between AP clients and other networks

## Uninstallation

To remove the WiFi monitor:

```bash
# Stop and disable the service
sudo systemctl stop ovbuddy-wifi
sudo systemctl disable ovbuddy-wifi

# Remove service file
sudo rm /etc/systemd/system/ovbuddy-wifi.service

# Remove script
sudo rm /home/pi/ovbuddy/wifi-monitor.py

# Reload systemd
sudo systemctl daemon-reload

# Optional: Remove packages (only if not used elsewhere)
# sudo apt-get remove hostapd dnsmasq
```

## Support

If you encounter issues:

1. Check the logs: `sudo journalctl -u ovbuddy-wifi -n 100`
2. Verify configuration: `cat /home/pi/ovbuddy/config.json`
3. Test WiFi manually: `sudo iwlist wlan0 scan`
4. Check service status: `sudo systemctl status ovbuddy-wifi`

For additional help, please open an issue on the GitHub repository.

