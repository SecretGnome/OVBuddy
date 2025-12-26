# Force Access Point Mode

## Overview

You can manually force the OVBuddy device into Access Point (AP) mode without waiting for automatic WiFi disconnection. This is useful for testing, troubleshooting, or reconfiguring WiFi settings.

## Methods to Force AP Mode

### Method 1: Web Interface (Easiest)

1. **Open Web Interface:**
   - Navigate to `http://ovbuddy.local:8080`
   - Or use the device's IP address

2. **Locate WiFi Section:**
   - Scroll to "WiFi Management" section
   - Look for the "Force AP Mode" button (orange/amber color)

3. **Click Button:**
   - Click "Force AP Mode"
   - Confirm the action when prompted

4. **Wait for AP Mode:**
   - Device will disconnect from WiFi
   - AP mode will activate in about 2 minutes
   - Display will show AP information

5. **Connect to AP:**
   - Look for WiFi network with configured SSID (default: "OVBuddy")
   - Connect to it
   - Access web interface at `http://192.168.4.1:8080`

### Method 2: Command Line (On Device)

**SSH into the device:**
```bash
ssh pi@ovbuddy.local
```

**Run the force AP script:**
```bash
sudo /home/pi/ovbuddy/force-ap-mode.sh
```

**Output:**
```
Forcing Access Point Mode...

Disconnecting from WiFi...
Disabling auto-reconnect...

WiFi disconnected.

The wifi-monitor service will switch to AP mode in about 2 minutes.
...
```

### Method 3: Remote Script (From Your Computer)

**Run the remote script:**
```bash
cd scripts
./force-ap-mode.sh
```

This script will:
1. Connect to the Raspberry Pi via SSH
2. Run the force AP mode script
3. Show status and instructions

**Requirements:**
- `.env` file with PI_HOST, PI_USER, PI_PASSWORD
- `sshpass` installed on your computer
- SSH access to the device

## How It Works

### Technical Process

1. **Create Force AP Flag:**
   ```bash
   # Create flag file that wifi-monitor checks on startup
   touch /var/lib/ovbuddy-force-ap
   ```

2. **Disconnect WiFi:**
   ```bash
   # Disconnect from current network (optional, speeds up process)
   wpa_cli -i wlan0 disconnect
   ```

3. **Reboot Device:**
   ```bash
   reboot
   ```

4. **After Reboot:**
   - WiFi monitor starts and detects force AP flag
   - Immediately enters AP mode (no 2-minute wait)
   - Removes the flag file
   - WiFi configuration is preserved

5. **AP Mode Active:**
   - Configures wlan0 with static IP (192.168.4.1)
   - Starts hostapd (access point)
   - Starts dnsmasq (DHCP/DNS)
   - Displays AP info on e-ink screen

6. **Ready:**
   - AP is active (about 1 minute total)
   - Web interface accessible at http://192.168.4.1:8080
   - Display shows connection details
   - WiFi configuration preserved for easy reconnection

### Why Reboot?

The device reboots because:
- **Clean State**: Ensures all network services start fresh
- **Reliable**: Guaranteed to enter AP mode via flag file
- **Simple**: No complex service manipulation needed
- **Preserves Config**: WiFi settings remain intact for easy reconnection

### Timeline

- **0:00** - Force AP mode triggered (flag created)
- **0:03** - Device reboots
- **0:30** - Device boots up
- **0:35** - WiFi monitor detects flag and enters AP mode immediately
- **1:00** - AP mode fully active
- **Total**: ~1 minute from trigger to AP ready (much faster than before!)

## Use Cases

### 1. Testing AP Fallback

Test that the AP fallback feature works correctly:

```bash
# Force AP mode
./scripts/force-ap-mode.sh

# Verify AP is created
# Connect to AP
# Access web interface
# Reconfigure WiFi
# Verify auto-reconnect works
```

### 2. Troubleshooting WiFi Issues

When WiFi isn't working:

1. Force AP mode via web interface
2. Connect to AP directly
3. Check WiFi status and logs
4. Scan for networks
5. Reconfigure WiFi settings

### 3. Initial Setup

Set up device in area with no WiFi:

1. Power on device
2. Wait for boot
3. Force AP mode via command line or wait for auto-AP
4. Connect to AP
5. Configure WiFi settings
6. Device connects to WiFi

### 4. Changing WiFi Networks

Switch to a different WiFi network:

1. Force AP mode
2. Connect to AP
3. Scan for new network
4. Configure new WiFi
5. Device automatically reconnects

### 5. Remote Troubleshooting

Help someone remotely:

1. Ask them to click "Force AP Mode" button
2. Guide them to connect to the AP
3. They can access web interface
4. You can guide them through WiFi configuration

## Web Interface Button

### Button Appearance

The "Force AP Mode" button is styled with an amber/orange color to indicate it's a significant action:

```html
<button type="button" id="forceApButton" onclick="forceApMode()" 
        style="background: #d97706;">
    Force AP Mode
</button>
```

### Button Behavior

**Before Click:**
- Button is enabled
- Shows "Force AP Mode" text

**On Click:**
- Shows confirmation dialog
- User must confirm action

**During Execution:**
- Button disabled
- Shows "Forcing AP Mode..." text

**After Success:**
- Button re-enabled
- Shows success message
- Displays AP information

**After Error:**
- Button re-enabled
- Shows error message

### Confirmation Dialog

```
Force Access Point mode?

This will:
1. Clear all WiFi configurations
2. Reboot the device
3. Enter AP mode after reboot

You will lose connection and need to connect to the AP.

Continue?
[Cancel] [OK]
```

### Success Alert

```
Device is Rebooting!

WiFi configuration has been cleared.
The device will reboot and enter Access Point mode.

Wait about 60 seconds, then:

1. Look for WiFi network: OVBuddy
2. Connect to it
3. Open: http://192.168.4.1:8080
4. Configure WiFi settings

This page will no longer be accessible until you reconnect.
```

## API Endpoint

### Endpoint Details

**URL:** `POST /api/wifi/force-ap`

**Authentication:** None (runs on device)

**Request:** No body required

**Response (Success):**
```json
{
  "success": true,
  "message": "Switching to Access Point mode...",
  "ap_ssid": "OVBuddy",
  "ap_ip": "192.168.4.1:8080"
}
```

**Response (Error):**
```json
{
  "success": false,
  "error": "Error message"
}
```

### Example Usage

**JavaScript:**
```javascript
fetch('/api/wifi/force-ap', {
    method: 'POST',
    headers: {
        'Content-Type': 'application/json',
    }
})
.then(response => response.json())
.then(data => {
    if (data.success) {
        console.log('AP mode forced:', data.ap_ssid);
    }
});
```

**curl:**
```bash
curl -X POST http://ovbuddy.local:8080/api/wifi/force-ap
```

## Security Considerations

### Permissions Required

- Script requires `sudo` (root) access
- Web interface uses passwordless sudo
- Must be configured during setup

### Risks

**Disconnection:**
- Immediately disconnects from WiFi
- Loses internet connectivity
- Services may be affected

**Access:**
- Anyone can access AP (if no password)
- Web interface is open on AP
- Consider setting AP password

**Mitigation:**
- Confirmation dialog prevents accidents
- AP password can be configured
- Display password option can be disabled
- Auto-reconnect when WiFi available

### Best Practices

1. **Set AP Password:**
   ```json
   {
     "ap_password": "SecurePassword123"
   }
   ```

2. **Hide Password on Display:**
   ```json
   {
     "display_ap_password": false
   }
   ```

3. **Limit Access:**
   - Only use when needed
   - Disable AP fallback in production if not needed

4. **Monitor Logs:**
   ```bash
   sudo journalctl -u ovbuddy-wifi -f
   ```

## Troubleshooting

### Button Doesn't Work

**Check passwordless sudo:**
```bash
ssh pi@ovbuddy.local
sudo -n echo "test"
```

If it asks for password, configure passwordless sudo:
```bash
echo 'pi ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/pi
```

### Script Not Found

**Check if script exists:**
```bash
ls -la /home/pi/ovbuddy/force-ap-mode.sh
```

**Redeploy if missing:**
```bash
cd scripts
./deploy.sh
```

### AP Mode Not Activating

**Check WiFi monitor service:**
```bash
sudo systemctl status ovbuddy-wifi
```

**Check logs:**
```bash
sudo journalctl -u ovbuddy-wifi -n 50
```

**Restart service:**
```bash
sudo systemctl restart ovbuddy-wifi
```

### Can't Connect to AP

**Check if AP is active:**
```bash
sudo iwconfig wlan0
# Should show Mode:Master
```

**Check IP address:**
```bash
ip addr show wlan0
# Should show 192.168.4.1
```

**Check hostapd:**
```bash
ps aux | grep hostapd
```

### Button Shows Error

**Check API endpoint:**
```bash
curl -X POST http://localhost:8080/api/wifi/force-ap
```

**Check web service logs:**
```bash
sudo journalctl -u ovbuddy-web -n 50
```

## Files Involved

### New Files

1. **`dist/force-ap-mode.sh`**
   - Script to force AP mode
   - Runs on the device
   - Requires sudo

2. **`scripts/force-ap-mode.sh`**
   - Remote wrapper script
   - Runs on your computer
   - Connects via SSH

### Modified Files

1. **`dist/ovbuddy.py`**
   - Added `/api/wifi/force-ap` endpoint
   - Calls force-ap-mode.sh script

2. **`dist/templates/index.html`**
   - Added "Force AP Mode" button
   - Styled with amber color

3. **`dist/static/js/app.js`**
   - Added `forceApMode()` function
   - Confirmation dialog
   - Success/error handling

## Examples

### Example 1: Quick Test

```bash
# Force AP mode
curl -X POST http://ovbuddy.local:8080/api/wifi/force-ap

# Wait 2 minutes or restart service
ssh pi@ovbuddy.local 'sudo systemctl restart ovbuddy-wifi'

# Check AP is active
ssh pi@ovbuddy.local 'sudo iwconfig wlan0'
```

### Example 2: Remote Troubleshooting

```bash
# From your computer
cd scripts
./force-ap-mode.sh

# Guide user to connect to AP
# User connects to "OVBuddy" network
# User opens http://192.168.4.1:8080
# Help them configure WiFi
```

### Example 3: Automated Testing

```bash
#!/bin/bash
# Test AP fallback feature

echo "1. Forcing AP mode..."
curl -X POST http://ovbuddy.local:8080/api/wifi/force-ap

echo "2. Waiting for AP mode..."
sleep 120

echo "3. Checking AP status..."
ssh pi@ovbuddy.local 'sudo iwconfig wlan0 | grep Mode'

echo "4. Testing web interface..."
curl http://192.168.4.1:8080

echo "5. Reconfiguring WiFi..."
# Configure WiFi via API

echo "6. Verifying reconnection..."
sleep 60
ping -c 3 ovbuddy.local
```

## Conclusion

The Force AP Mode feature provides a convenient way to manually trigger Access Point mode without waiting for automatic WiFi disconnection. It's accessible via web interface, command line, or remote script, making it useful for testing, troubleshooting, and initial setup.

Key benefits:
- **Quick Access**: No waiting for disconnection
- **User-Friendly**: Simple button in web interface
- **Flexible**: Multiple access methods
- **Safe**: Confirmation dialog prevents accidents
- **Documented**: Clear instructions and examples

For more information about the WiFi AP fallback feature, see [WIFI_AP_FALLBACK.md](WIFI_AP_FALLBACK.md).

