# Access Point Display Feature

## Overview

When the Raspberry Pi switches to Access Point (AP) mode due to WiFi disconnection, it now automatically displays the AP information on the e-ink screen, making it easy to connect without needing to check logs or documentation.

## What Gets Displayed

When in AP mode, the e-ink screen shows:

```
┌─────────────────────────────┐
│   Access Point Mode         │
├─────────────────────────────┤
│ WiFi Network:               │
│   OVBuddy                   │
│                             │
│ Password:                   │
│   ******** (or actual pwd)  │
│                             │
│ Web Interface:              │
│   http://192.168.4.1:8080   │
│                             │
│ Connect to this network     │
│ to configure WiFi           │
└─────────────────────────────┘
```

## Configuration

### Display Password on Screen

You can control whether the actual password is shown on the screen:

**Via Web Interface:**
1. Open `http://ovbuddy.local:8080`
2. Scroll to "Access Point Settings"
3. Check "Display password on screen when in AP mode"
4. Save configuration

**Via config.json:**
```json
{
  "display_ap_password": true
}
```

- `true`: Shows the actual password on screen
- `false` (default): Shows `********` instead

### Security Considerations

**When to enable password display:**
- ✅ During initial setup
- ✅ When device is in a secure location
- ✅ For easier troubleshooting
- ✅ When using a temporary password

**When to disable password display:**
- ✅ In production/public environments
- ✅ When using a permanent password
- ✅ For better security
- ✅ When device is visible to others

## How It Works

### Automatic Display

1. **WiFi Disconnection**: Device loses connection to configured WiFi
2. **Wait Period**: Waits 2 minutes to avoid false triggers
3. **Switch to AP Mode**: Creates access point with configured SSID
4. **Display AP Info**: Automatically shows AP information on e-ink screen
5. **Stay Visible**: Information remains on screen until WiFi reconnects

### Display Script

The system uses a dedicated script (`display_ap_info.py`) to show AP information:

```python
# Called automatically by wifi-monitor.py
python3 /home/pi/ovbuddy/display_ap_info.py
```

This script:
- Reads configuration from `config.json`
- Gets AP SSID and password
- Checks if password should be displayed
- Renders information on e-ink screen
- Leaves display showing (doesn't sleep)

### Integration

The display is triggered by `wifi-monitor.py` when switching to AP mode:

```python
# In switch_to_ap_mode() function
try:
    logger.info("Displaying AP information on e-ink screen...")
    result = subprocess.run(['python3', 'display_ap_info.py'], ...)
    if result.returncode == 0:
        logger.info("AP information displayed on screen")
except Exception as e:
    logger.error(f"Error displaying AP info: {e}")
    # Don't fail AP mode if display fails
```

## Display Layout

### With Password Hidden (default)

```
Access Point Mode
─────────────────────────
WiFi Network:
  OVBuddy

Password:
  ********

Web Interface:
  http://192.168.4.1:8080

Connect to this network
to configure WiFi
```

### With Password Shown

```
Access Point Mode
─────────────────────────
WiFi Network:
  OVBuddy

Password:
  MySecurePassword123

Web Interface:
  http://192.168.4.1:8080

Connect to this network
to configure WiFi
```

### Open Network (no password)

```
Access Point Mode
─────────────────────────
WiFi Network:
  OVBuddy

Password:
  (open network)

Web Interface:
  http://192.168.4.1:8080

Connect to this network
to configure WiFi
```

## Display Features

### Text Wrapping

- **Long SSID**: Truncated with ellipsis if too long
- **Long Password**: Split across multiple lines if needed
- **Automatic Layout**: Adjusts spacing based on content

### Display Modes

- **Inverted**: Respects `inverted` config setting
- **Flipped**: Respects `flip_display` config setting
- **Font**: Uses default system font with bold for headers

### Error Handling

- If display fails, AP mode continues normally
- Error logged but doesn't prevent AP functionality
- Graceful fallback if display hardware unavailable

## Testing

### Test AP Display

1. **Trigger AP Mode Manually:**
   ```bash
   ssh pi@ovbuddy.local
   sudo wpa_cli -i wlan0 disconnect
   # Wait 2 minutes
   ```

2. **Check Display:**
   - E-ink screen should show AP information
   - SSID should match configuration
   - Password shown/hidden based on setting

3. **Verify Information:**
   ```bash
   sudo journalctl -u ovbuddy-wifi -f
   # Look for "AP information displayed on screen"
   ```

### Test Password Display Toggle

1. **Enable password display:**
   ```bash
   # Via web interface or edit config.json
   "display_ap_password": true
   ```

2. **Trigger AP mode**

3. **Check screen shows actual password**

4. **Disable password display:**
   ```bash
   "display_ap_password": false
   ```

5. **Trigger AP mode again**

6. **Check screen shows asterisks**

### Manual Display Test

You can test the display script directly:

```bash
ssh pi@ovbuddy.local
cd /home/pi/ovbuddy
python3 display_ap_info.py
```

This will:
- Read current configuration
- Display AP info on screen
- Print status to console

## Troubleshooting

### Display Not Showing

**Check if script exists:**
```bash
ls -la /home/pi/ovbuddy/display_ap_info.py
```

**Check logs:**
```bash
sudo journalctl -u ovbuddy-wifi -n 50 | grep -i display
```

**Test manually:**
```bash
cd /home/pi/ovbuddy
python3 display_ap_info.py
```

### Wrong Information Displayed

**Check configuration:**
```bash
cat /home/pi/ovbuddy/config.json | grep -A3 ap_
```

**Verify settings:**
- `ap_ssid`: Should match actual AP name
- `ap_password`: Should match actual password
- `display_ap_password`: Controls visibility

### Display Stays After Reconnection

This is normal behavior:
- Display shows AP info while in AP mode
- When WiFi reconnects, normal display resumes
- Next refresh cycle will show departure board

To force immediate update:
```bash
sudo systemctl restart ovbuddy
```

## Configuration Examples

### Example 1: Open Network with Display

```json
{
  "ap_fallback_enabled": true,
  "ap_ssid": "OVBuddy-Setup",
  "ap_password": "",
  "display_ap_password": false
}
```

Screen shows:
```
WiFi Network: OVBuddy-Setup
Password: (open network)
```

### Example 2: Secure Network, Hide Password

```json
{
  "ap_fallback_enabled": true,
  "ap_ssid": "OVBuddy",
  "ap_password": "SecurePass123",
  "display_ap_password": false
}
```

Screen shows:
```
WiFi Network: OVBuddy
Password: ********
```

### Example 3: Secure Network, Show Password

```json
{
  "ap_fallback_enabled": true,
  "ap_ssid": "OVBuddy",
  "ap_password": "SecurePass123",
  "display_ap_password": true
}
```

Screen shows:
```
WiFi Network: OVBuddy
Password: SecurePass123
```

## Implementation Details

### Files Modified

1. **`dist/config.json`**
   - Added `display_ap_password` option

2. **`dist/ovbuddy.py`**
   - Added `DISPLAY_AP_PASSWORD` global variable
   - Added `render_ap_info()` function
   - Updated config load/save/update functions

3. **`dist/wifi-monitor.py`**
   - Added display trigger in `switch_to_ap_mode()`
   - Calls `display_ap_info.py` when entering AP mode

4. **`dist/display_ap_info.py`** (new)
   - Standalone script to display AP info
   - Called by wifi-monitor.py
   - Reads config and renders to e-ink

5. **`dist/templates/index.html`**
   - Added password display checkbox

6. **`dist/static/js/app.js`**
   - Added password display field handling

### Function: render_ap_info()

```python
def render_ap_info(ssid, password=None, display_password=False, epd=None, test_mode=False):
    """Render Access Point information on the e-ink display
    
    Args:
        ssid: The AP SSID to display
        password: The AP password (optional)
        display_password: Whether to show the password on screen
        epd: The e-ink display object
        test_mode: If True, print to console instead of displaying
    """
```

Features:
- Centered title
- Separator line
- Bold labels
- Text wrapping for long content
- Respects display settings (inverted, flipped)
- Error handling

## Future Enhancements

Possible improvements:

1. **QR Code**: Add QR code for easy WiFi connection
2. **Countdown**: Show time until WiFi retry
3. **Signal Strength**: Show when scanning for WiFi
4. **Multiple Languages**: Support different languages
5. **Custom Messages**: Allow custom instructions
6. **Animation**: Animated indicators for scanning
7. **Status Updates**: Show "Scanning..." when checking for WiFi

## Conclusion

The AP display feature makes it much easier to connect to the device when WiFi is unavailable. Users can see the exact network name and password (if configured) directly on the e-ink screen, eliminating the need to check documentation or logs.

The feature is:
- **Automatic**: Displays when entering AP mode
- **Configurable**: Control password visibility
- **Secure**: Password hidden by default
- **Reliable**: Continues AP mode even if display fails
- **User-Friendly**: Clear, easy-to-read layout

For more information about the WiFi AP fallback feature, see [WIFI_AP_FALLBACK.md](WIFI_AP_FALLBACK.md).


