# Force AP Mode - Auto-Reconnect Fix

## The Problem

When using Force AP mode, the Raspberry Pi was "falling back" to known WiFi networks instead of entering AP mode. This happened because:

### Root Cause

The original `force-ap-mode.sh` script only **disconnected** from WiFi but didn't **prevent auto-reconnection**:

```bash
# Old code - only disconnects temporarily
nmcli device disconnect wlan0
# or
wpa_cli -i wlan0 disconnect
```

### What Was Happening

1. **Force AP script runs:**
   - Creates flag file `/var/lib/ovbuddy-force-ap`
   - Disconnects from WiFi
   - Reboots device

2. **After reboot:**
   - NetworkManager/wpa_supplicant starts
   - Automatically reconnects to known networks (because auto-connect is still enabled)
   - Device gets IP address and connects to WiFi
   - wifi-monitor service starts
   - Checks flag file, but device is already connected
   - Stays in client mode instead of switching to AP mode

### Timeline Issue

```
Time    Event
----    -----
0:00    Device boots
0:20    NetworkManager starts
0:25    Auto-connects to known WiFi
0:30    wifi-monitor service starts
0:31    Checks flag file
0:32    Sees WiFi is connected, stays in client mode
```

The problem: **Auto-reconnect happens before wifi-monitor can act on the flag file.**

## The Solution

The fix prevents auto-reconnection by disabling it before rebooting:

### For NetworkManager

```bash
# Disconnect from current network
nmcli device disconnect wlan0

# Disable auto-connect for all WiFi connections
for conn in $(nmcli -t -f NAME,TYPE connection show | grep ':802-11-wireless$' | cut -d: -f1); do
    nmcli connection modify "$conn" connection.autoconnect no
done

# Set wlan0 to unmanaged temporarily
nmcli device set wlan0 managed no
```

### For wpa_supplicant

```bash
# Disconnect from current network
wpa_cli -i wlan0 disconnect

# Disable all networks
wpa_cli -i wlan0 disable_network all

# Save configuration
wpa_cli -i wlan0 save_config
```

### After Reboot

Now the timeline looks like this:

```
Time    Event
----    -----
0:00    Device boots
0:20    NetworkManager starts
0:25    Sees auto-connect disabled, doesn't connect
0:30    wifi-monitor service starts
0:31    Checks flag file
0:32    Sees WiFi not connected, enters AP mode
0:45    AP mode active
```

## Changes Made

### 1. Updated `force-ap-mode.sh`

**Location:** `dist/force-ap-mode.sh`

**Changes:**
- Added logic to disable auto-connect for NetworkManager connections
- Added logic to disable all networks for wpa_supplicant
- Set wlan0 to unmanaged for NetworkManager
- These changes prevent auto-reconnection after reboot

**NetworkManager method:**
```bash
# Disable auto-connect for all WiFi connections
for conn in $(nmcli -t -f NAME,TYPE connection show | grep ':802-11-wireless$' | cut -d: -f1); do
    echo "    Disabling auto-connect for: $conn"
    nmcli connection modify "$conn" connection.autoconnect no 2>/dev/null || true
done

# Set wlan0 to unmanaged temporarily
nmcli device set wlan0 managed no 2>/dev/null || true
```

**wpa_supplicant method:**
```bash
# Disable all networks
wpa_cli -i wlan0 disable_network all 2>/dev/null || true
wpa_cli -i wlan0 save_config 2>/dev/null || true
```

### 2. Updated `wifi-monitor.py`

**Location:** `dist/wifi-monitor.py`

**Changes:**
- Added logic to re-enable auto-connect when switching back to client mode
- This ensures WiFi works normally after exiting AP mode

**NetworkManager method:**
```python
# Re-enable auto-connect for all WiFi connections
logger.info("Re-enabling auto-connect for WiFi connections...")
result = subprocess.run(
    ['sudo', 'nmcli', '-t', '-f', 'NAME,TYPE', 'connection', 'show'],
    capture_output=True,
    text=True,
    timeout=5
)
if result.returncode == 0:
    for line in result.stdout.strip().split('\n'):
        if ':802-11-wireless' in line:
            conn_name = line.split(':')[0]
            logger.info(f"Enabling auto-connect for: {conn_name}")
            subprocess.run(
                ['sudo', 'nmcli', 'connection', 'modify', conn_name, 'connection.autoconnect', 'yes'],
                timeout=5,
                capture_output=True
            )
```

**wpa_supplicant method:**
```python
# Re-enable all networks
logger.info("Re-enabling all WiFi networks...")
subprocess.run(['sudo', 'wpa_cli', '-i', 'wlan0', 'enable_network', 'all'], timeout=5)
```

### 3. Created Diagnostic Script

**Location:** `scripts/diagnose-force-ap.sh`

**Purpose:**
- Diagnose why Force AP mode might not be working
- Check WiFi manager type (NetworkManager vs wpa_supplicant)
- Check current WiFi connection status
- Check if networks have auto-connect enabled/disabled
- Check if force AP flag exists
- Check wifi-monitor service status
- Check if device is in AP mode
- Provide recommendations based on findings

**Usage:**
```bash
cd scripts
./diagnose-force-ap.sh
```

## How to Test

### 1. Deploy Updated Files

```bash
cd scripts
./deploy.sh
```

### 2. Run Diagnostics (Before)

```bash
cd scripts
./diagnose-force-ap.sh
```

This will show:
- Current WiFi connection
- Auto-connect status for networks
- Service status

### 3. Force AP Mode

```bash
cd scripts
./force-ap-mode.sh
```

Or via web interface:
- Open http://ovbuddy.local:8080
- Click "Force AP Mode" button
- Confirm action

### 4. Wait for Reboot

- Device will reboot (~30 seconds)
- wifi-monitor will start (~30 seconds)
- AP mode will activate (~15 seconds)
- Total: ~75 seconds

### 5. Verify AP Mode

**Look for WiFi network:**
- SSID: Check `config.json` (default: "OVBuddy")
- Connect to it

**Access web interface:**
- URL: http://192.168.4.1:8080
- Should see OVBuddy interface

**Check display:**
- E-ink screen should show AP information

### 6. Run Diagnostics (After)

From another device connected to the AP:

```bash
cd scripts
./diagnose-force-ap.sh
```

This will show:
- Device is in AP mode
- AP IP address
- hostapd status

### 7. Return to Client Mode

**Via web interface:**
- Open http://192.168.4.1:8080
- Scan for WiFi networks
- Select your network
- Enter password
- Click "Connect"

**Device will:**
- Re-enable auto-connect
- Switch to client mode
- Connect to WiFi
- Resume normal operation

## Verification Commands

### Check Auto-Connect Status (NetworkManager)

```bash
# List all WiFi connections and their auto-connect status
ssh pi@ovbuddy.local
nmcli -f NAME,AUTOCONNECT connection show | grep -v '^lo'
```

Expected output (normal mode):
```
NAME                AUTOCONNECT
MyWiFiNetwork       yes
```

Expected output (after force AP, before reboot):
```
NAME                AUTOCONNECT
MyWiFiNetwork       no
```

### Check Network Status (wpa_supplicant)

```bash
# List all networks and their status
ssh pi@ovbuddy.local
sudo wpa_cli -i wlan0 list_networks
```

Expected output (normal mode):
```
network id / ssid / bssid / flags
0       MyWiFiNetwork   any     [CURRENT]
```

Expected output (after force AP, before reboot):
```
network id / ssid / bssid / flags
0       MyWiFiNetwork   any     [DISABLED]
```

### Check wlan0 Management (NetworkManager)

```bash
# Check if wlan0 is managed
ssh pi@ovbuddy.local
nmcli device status | grep wlan0
```

Expected output (normal mode):
```
wlan0   wifi      connected    MyWiFiNetwork
```

Expected output (after force AP, before reboot):
```
wlan0   wifi      unmanaged    --
```

## Troubleshooting

### Issue: Networks Still Auto-Connecting

**Symptom:**
- Force AP mode triggered
- Device reboots
- Reconnects to WiFi instead of entering AP mode

**Diagnosis:**
```bash
cd scripts
./diagnose-force-ap.sh
```

Look for:
- "auto-connect: enabled" (should be disabled)
- "ENABLED" networks (should be disabled)

**Fix:**
```bash
# Manually disable auto-connect (NetworkManager)
ssh pi@ovbuddy.local
nmcli connection modify "MyWiFiNetwork" connection.autoconnect no

# Or disable networks (wpa_supplicant)
ssh pi@ovbuddy.local
sudo wpa_cli -i wlan0 disable_network all
sudo wpa_cli -i wlan0 save_config
```

Then reboot:
```bash
ssh pi@ovbuddy.local 'sudo reboot'
```

### Issue: Can't Reconnect After AP Mode

**Symptom:**
- Exited AP mode
- Device doesn't reconnect to WiFi
- Auto-connect still disabled

**Diagnosis:**
```bash
cd scripts
./diagnose-force-ap.sh
```

Look for:
- "auto-connect: disabled" (should be enabled)
- "DISABLED" networks (should be enabled)

**Fix:**
```bash
# Manually re-enable auto-connect (NetworkManager)
ssh pi@ovbuddy.local
nmcli connection modify "MyWiFiNetwork" connection.autoconnect yes
nmcli device connect wlan0

# Or enable networks (wpa_supplicant)
ssh pi@ovbuddy.local
sudo wpa_cli -i wlan0 enable_network all
sudo wpa_cli -i wlan0 reconfigure
```

### Issue: wifi-monitor Not Re-enabling Auto-Connect

**Symptom:**
- Switched to client mode via web interface
- WiFi still not auto-connecting
- Logs show no errors

**Check logs:**
```bash
ssh pi@ovbuddy.local
sudo journalctl -u ovbuddy-wifi -n 50
```

Look for:
- "Re-enabling auto-connect for WiFi connections..."
- "Enabling auto-connect for: <network-name>"

**Fix:**
```bash
# Restart wifi-monitor service
ssh pi@ovbuddy.local
sudo systemctl restart ovbuddy-wifi
```

## Technical Details

### NetworkManager Auto-Connect

NetworkManager stores connection profiles in `/etc/NetworkManager/system-connections/`.

Each profile has an `autoconnect` setting:

```ini
[connection]
id=MyWiFiNetwork
type=wifi
autoconnect=true  # or false
```

When `autoconnect=false`:
- NetworkManager won't automatically connect to this network
- Manual connection still possible
- Persists across reboots

### wpa_supplicant Network Disable

wpa_supplicant stores networks in `/etc/wpa_supplicant/wpa_supplicant.conf`.

Each network can be disabled:

```
network={
    ssid="MyWiFiNetwork"
    psk="password"
    disabled=1  # or 0 for enabled
}
```

When `disabled=1`:
- wpa_supplicant won't try to connect to this network
- Manual connection still possible via `wpa_cli enable_network <id>`
- Persists across reboots (if saved with `save_config`)

### wlan0 Unmanaged State

NetworkManager can be told to not manage specific interfaces:

```bash
# Set to unmanaged
nmcli device set wlan0 managed no

# Set back to managed
nmcli device set wlan0 managed yes
```

When unmanaged:
- NetworkManager ignores the interface
- Manual configuration possible
- Allows hostapd to control the interface
- Does NOT persist across reboots (reverts to managed)

## Benefits of This Fix

### 1. Reliable AP Mode Entry

- Device will always enter AP mode when forced
- No race condition with auto-reconnect
- Predictable behavior

### 2. Preserves Configuration

- WiFi credentials remain saved
- Only auto-connect is disabled temporarily
- Easy to reconnect via web interface

### 3. Automatic Recovery

- wifi-monitor re-enables auto-connect when returning to client mode
- No manual intervention needed
- WiFi works normally after AP mode

### 4. Works with Both WiFi Managers

- Supports NetworkManager
- Supports wpa_supplicant
- Automatic detection

### 5. Diagnostic Tools

- Easy to verify current state
- Clear troubleshooting steps
- Actionable recommendations

## Summary

The Force AP mode now works reliably by:

1. **Preventing auto-reconnect** before rebooting
2. **Giving wifi-monitor time** to detect the flag and enter AP mode
3. **Re-enabling auto-connect** when returning to client mode
4. **Providing diagnostics** to verify behavior

This ensures the device enters AP mode as expected and can easily return to normal WiFi operation.

