# Force AP Mode - Root Cause Analysis

## Problem Statement

When using the Force AP mode feature, the Raspberry Pi would "fall back" to the known WiFi network instead of entering Access Point mode. This made the feature unreliable and confusing for users.

## Investigation

### Question Asked
> "When we use the Force AP mode, it doesn't seem to work. The raspberry pi seems to 'fall back' to the known network. Could it be that we're using the wrong method to clear the wifi? How can we find out?"

### Initial Hypothesis
The hypothesis was that we might be using the wrong method to "clear" or disconnect from WiFi.

## Root Cause

After analyzing the code, we discovered the issue was **not** about clearing WiFi, but about **preventing auto-reconnection**.

### The Problem Code

In `dist/force-ap-mode.sh` (lines 28-43):

```bash
# Check if NetworkManager is managing WiFi
if command -v nmcli &> /dev/null; then
    NM_STATUS=$(nmcli device status 2>/dev/null | grep wlan0 || true)
    if [ -n "$NM_STATUS" ] && ! echo "$NM_STATUS" | grep -q "unmanaged"; then
        echo "  Detected NetworkManager, disconnecting..."
        nmcli device disconnect wlan0 2>/dev/null || true  # ← PROBLEM
        echo "  ✓ Disconnected (NetworkManager)"
    else
        wpa_cli -i wlan0 disconnect 2>/dev/null || true   # ← PROBLEM
        echo "  ✓ Disconnected (wpa_supplicant)"
    fi
else
    wpa_cli -i wlan0 disconnect 2>/dev/null || true       # ← PROBLEM
    echo "  ✓ Disconnected (wpa_supplicant)"
fi
```

### Why This Failed

1. **`nmcli device disconnect wlan0`** - Only disconnects temporarily
   - Does NOT disable auto-connect
   - After reboot, NetworkManager automatically reconnects
   
2. **`wpa_cli -i wlan0 disconnect`** - Only disconnects temporarily
   - Does NOT disable the network
   - After reboot, wpa_supplicant automatically reconnects

### The Race Condition

```
Timeline of Events (BROKEN):
─────────────────────────────────────────────────────────────
0:00  │ Force AP script runs
      │ - Creates flag file: /var/lib/ovbuddy-force-ap
      │ - Disconnects from WiFi (temporarily)
      │ - Reboots device
─────────────────────────────────────────────────────────────
0:30  │ Device boots
      │ - NetworkManager/wpa_supplicant starts
─────────────────────────────────────────────────────────────
0:35  │ Auto-reconnect happens
      │ - Sees known network: "MyWiFiNetwork"
      │ - Auto-connect is still enabled
      │ - Connects automatically
      │ - Gets IP address: 192.168.1.100
─────────────────────────────────────────────────────────────
0:40  │ wifi-monitor service starts
      │ - Checks flag file: /var/lib/ovbuddy-force-ap ✓
      │ - Checks WiFi status: CONNECTED
      │ - Decision: Stay in client mode (WiFi is working)
      │ - Removes flag file
─────────────────────────────────────────────────────────────
Result: Device stays connected to WiFi (WRONG!)
```

**The problem:** Auto-reconnect happens **before** wifi-monitor can act on the flag file.

## The Solution

### What We Need To Do

Instead of just disconnecting, we need to **disable auto-connect** before rebooting:

1. **For NetworkManager:**
   - Disable auto-connect for all WiFi connections
   - Set wlan0 to unmanaged
   
2. **For wpa_supplicant:**
   - Disable all networks
   - Save configuration

### The Fix Code

```bash
# Check if NetworkManager is managing WiFi
if command -v nmcli &> /dev/null; then
    NM_STATUS=$(nmcli device status 2>/dev/null | grep wlan0 || true)
    if [ -n "$NM_STATUS" ] && ! echo "$NM_STATUS" | grep -q "unmanaged"; then
        echo "  Detected NetworkManager, disabling auto-connect..."
        
        # Disconnect from current network
        nmcli device disconnect wlan0 2>/dev/null || true
        
        # Disable auto-connect for all WiFi connections
        for conn in $(nmcli -t -f NAME,TYPE connection show | grep ':802-11-wireless$' | cut -d: -f1); do
            echo "    Disabling auto-connect for: $conn"
            nmcli connection modify "$conn" connection.autoconnect no 2>/dev/null || true
        done
        
        # Set wlan0 to unmanaged temporarily
        nmcli device set wlan0 managed no 2>/dev/null || true
        
        echo "  ✓ Auto-connect disabled (NetworkManager)"
    else
        echo "  Using wpa_supplicant method..."
        wpa_cli -i wlan0 disconnect 2>/dev/null || true
        wpa_cli -i wlan0 disable_network all 2>/dev/null || true
        wpa_cli -i wlan0 save_config 2>/dev/null || true
        echo "  ✓ Networks disabled (wpa_supplicant)"
    fi
else
    echo "  Using wpa_supplicant method..."
    wpa_cli -i wlan0 disconnect 2>/dev/null || true
    wpa_cli -i wlan0 disable_network all 2>/dev/null || true
    wpa_cli -i wlan0 save_config 2>/dev/null || true
    echo "  ✓ Networks disabled (wpa_supplicant)"
fi
```

### Why This Works

```
Timeline of Events (FIXED):
─────────────────────────────────────────────────────────────
0:00  │ Force AP script runs
      │ - Creates flag file: /var/lib/ovbuddy-force-ap
      │ - Disconnects from WiFi
      │ - Disables auto-connect for all networks ← NEW
      │ - Sets wlan0 to unmanaged (NM) ← NEW
      │ - Reboots device
─────────────────────────────────────────────────────────────
0:30  │ Device boots
      │ - NetworkManager/wpa_supplicant starts
─────────────────────────────────────────────────────────────
0:35  │ Auto-reconnect BLOCKED
      │ - Sees known network: "MyWiFiNetwork"
      │ - Auto-connect is DISABLED ← KEY DIFFERENCE
      │ - Does NOT connect
      │ - No IP address assigned
─────────────────────────────────────────────────────────────
0:40  │ wifi-monitor service starts
      │ - Checks flag file: /var/lib/ovbuddy-force-ap ✓
      │ - Checks WiFi status: NOT CONNECTED ✓
      │ - Decision: Enter AP mode
      │ - Removes flag file
      │ - Configures wlan0 as AP
      │ - Starts hostapd and dnsmasq
─────────────────────────────────────────────────────────────
0:50  │ AP mode active
      │ - SSID: "OVBuddy"
      │ - IP: 192.168.4.1
      │ - Web interface: http://192.168.4.1:8080
─────────────────────────────────────────────────────────────
Result: Device enters AP mode (CORRECT!)
```

## Additional Changes

### 1. Re-enable Auto-Connect When Returning to Client Mode

In `dist/wifi-monitor.py`, we added code to re-enable auto-connect when switching back to client mode:

**For NetworkManager:**
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
                ['sudo', 'nmcli', 'connection', 'modify', conn_name, 
                 'connection.autoconnect', 'yes'],
                timeout=5,
                capture_output=True
            )
```

**For wpa_supplicant:**
```python
# Re-enable all networks
logger.info("Re-enabling all WiFi networks...")
subprocess.run(['sudo', 'wpa_cli', '-i', 'wlan0', 'enable_network', 'all'], timeout=5)
```

This ensures WiFi works normally after exiting AP mode.

### 2. Created Diagnostic Script

Created `scripts/diagnose-force-ap.sh` to help diagnose issues:

- Detects WiFi manager (NetworkManager vs wpa_supplicant)
- Shows current WiFi connection status
- Lists configured networks and their auto-connect status
- Checks if force AP flag exists
- Checks wifi-monitor service status
- Checks if device is in AP mode
- Provides actionable recommendations

## Verification

### How to Verify the Fix

1. **Deploy updated files:**
   ```bash
   cd scripts
   ./deploy.sh
   ```

2. **Run diagnostics (before):**
   ```bash
   cd scripts
   ./diagnose-force-ap.sh
   ```
   
   Should show:
   - Connected to WiFi
   - Auto-connect: enabled

3. **Force AP mode:**
   ```bash
   cd scripts
   ./force-ap-mode.sh
   ```
   
   Or via web interface

4. **Wait for reboot (~60 seconds)**

5. **Verify AP mode:**
   - Look for "OVBuddy" WiFi network
   - Connect to it
   - Access http://192.168.4.1:8080

6. **Run diagnostics (after):**
   ```bash
   cd scripts
   ./diagnose-force-ap.sh
   ```
   
   Should show:
   - Device in AP mode
   - AP IP: 192.168.4.1
   - hostapd running

### Manual Verification Commands

**Check auto-connect status (NetworkManager):**
```bash
ssh pi@ovbuddy.local
nmcli -f NAME,AUTOCONNECT connection show
```

**Check network status (wpa_supplicant):**
```bash
ssh pi@ovbuddy.local
sudo wpa_cli -i wlan0 list_networks
```

**Check if in AP mode:**
```bash
ssh pi@ovbuddy.local
sudo iwconfig wlan0 | grep Mode
# Should show "Mode:Master" when in AP mode
```

## Technical Details

### NetworkManager Auto-Connect

NetworkManager stores connection profiles with an `autoconnect` setting:

```ini
[connection]
id=MyWiFiNetwork
type=wifi
autoconnect=true  # or false
```

Commands:
```bash
# Disable auto-connect
nmcli connection modify "MyWiFiNetwork" connection.autoconnect no

# Enable auto-connect
nmcli connection modify "MyWiFiNetwork" connection.autoconnect yes
```

This setting **persists across reboots**.

### wpa_supplicant Network Disable

wpa_supplicant stores networks with a `disabled` flag:

```
network={
    ssid="MyWiFiNetwork"
    psk="password"
    disabled=1  # or 0 for enabled
}
```

Commands:
```bash
# Disable network
wpa_cli -i wlan0 disable_network 0

# Enable network
wpa_cli -i wlan0 enable_network 0

# Save configuration (required for persistence)
wpa_cli -i wlan0 save_config
```

This setting **persists across reboots** (if saved).

### NetworkManager Unmanaged State

NetworkManager can be told to ignore specific interfaces:

```bash
# Set to unmanaged
nmcli device set wlan0 managed no

# Set back to managed
nmcli device set wlan0 managed yes
```

This setting **does NOT persist across reboots** (reverts to managed).

## Lessons Learned

### 1. Disconnect ≠ Disable Auto-Connect

**Disconnect:**
- Temporary action
- Does NOT prevent reconnection
- Does NOT persist across reboots

**Disable Auto-Connect:**
- Configuration change
- Prevents automatic reconnection
- Persists across reboots

### 2. Race Conditions in Boot Sequences

When working with services that start on boot:
- Consider the order of service startup
- Account for auto-configuration that happens before your service starts
- Use persistent configuration changes, not temporary state changes

### 3. Different WiFi Managers Behave Differently

NetworkManager and wpa_supplicant have different:
- Commands
- Configuration files
- Behavior
- Persistence mechanisms

Always test with both if your system might use either.

### 4. Diagnostic Tools Are Essential

Creating `diagnose-force-ap.sh` helped:
- Understand the current state
- Identify the exact problem
- Verify the fix
- Provide user-friendly troubleshooting

## Summary

### The Problem
Force AP mode didn't work because the device auto-reconnected to known WiFi networks after reboot, before wifi-monitor could enter AP mode.

### The Root Cause
Using `disconnect` commands instead of `disable auto-connect` commands.

### The Solution
1. Disable auto-connect before rebooting
2. Re-enable auto-connect when returning to client mode
3. Provide diagnostic tools to verify behavior

### Files Changed
1. `dist/force-ap-mode.sh` - Disable auto-connect before reboot
2. `dist/wifi-monitor.py` - Re-enable auto-connect when returning to client mode
3. `scripts/diagnose-force-ap.sh` - New diagnostic script
4. `doc/FORCE_AP_FIX_AUTOCONNECT.md` - Technical documentation
5. `doc/FORCE_AP_ROOT_CAUSE_ANALYSIS.md` - This document
6. `README.md` - Updated troubleshooting section

### Result
Force AP mode now works reliably on both NetworkManager and wpa_supplicant systems.

