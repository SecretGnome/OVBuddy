# NetworkManager Support

## Overview

OVBuddy now fully supports both **NetworkManager** and **wpa_supplicant** for WiFi management. The system automatically detects which WiFi manager is in use and adapts accordingly.

## The Problem

On Raspberry Pi OS Bullseye/Bookworm, WiFi is often managed by NetworkManager instead of the traditional wpa_supplicant:

- **wpa_supplicant**: Stores WiFi networks in `/etc/wpa_supplicant/wpa_supplicant.conf`
- **NetworkManager**: Stores WiFi networks as connection profiles in `/etc/NetworkManager/system-connections/`

When NetworkManager is active:
- `/etc/wpa_supplicant/wpa_supplicant.conf` is **ignored**
- `wpa_cli` commands don't work
- WiFi networks are managed through `nmcli` commands

## The Solution

OVBuddy now:
1. **Auto-detects** which WiFi manager is in use at startup
2. **Adapts** all WiFi operations to work with the detected manager
3. **Switches correctly** between client mode and AP mode
4. **Preserves** WiFi configuration regardless of manager

## How It Works

### Detection

On startup, `wifi-monitor.py` checks:

```python
# Check if NetworkManager is managing wlan0
nmcli device status | grep wlan0

# If not, check if wpa_supplicant is active
systemctl is-active wpa_supplicant
```

The detected manager is logged:
```
WiFi manager detected: networkmanager
```
or
```
WiFi manager detected: wpa_supplicant
```

### WiFi Operations

#### Checking WiFi Connection
- **NetworkManager**: Uses `nmcli device status`
- **wpa_supplicant**: Uses `iwgetid` and `wpa_cli status`

#### Scanning for Networks
- **NetworkManager**: Uses `nmcli device wifi list`
- **wpa_supplicant**: Uses `iwlist wlan0 scan`

#### Listing Configured Networks
- **NetworkManager**: Uses `nmcli connection show`
- **wpa_supplicant**: Uses `wpa_cli list_networks`

### Switching to AP Mode

When entering AP mode:

**NetworkManager:**
```bash
# Set wlan0 to unmanaged (NetworkManager won't touch it)
nmcli device set wlan0 managed no

# Toggle WiFi radio to apply changes
nmcli radio wifi off
nmcli radio wifi on

# Now we can configure wlan0 manually for AP mode
```

**wpa_supplicant:**
```bash
# Stop wpa_supplicant and dhcpcd
systemctl stop wpa_supplicant
systemctl stop dhcpcd

# Configure wlan0 for AP mode
```

### Switching to Client Mode

When returning to client mode:

**NetworkManager:**
```bash
# Re-enable NetworkManager management
nmcli device set wlan0 managed yes

# Toggle WiFi to reconnect
nmcli radio wifi off
nmcli radio wifi on

# Trigger connection
nmcli device connect wlan0
```

**wpa_supplicant:**
```bash
# Restart services
systemctl start dhcpcd
systemctl start wpa_supplicant

# Trigger reconnection
wpa_cli -i wlan0 reconfigure
```

## Force AP Mode with NetworkManager

The `force-ap-mode.sh` script now detects and handles both managers:

```bash
# Detects NetworkManager
if nmcli device status | grep wlan0 | grep -v unmanaged; then
    # Disconnect using NetworkManager
    nmcli device disconnect wlan0
else
    # Disconnect using wpa_cli
    wpa_cli -i wlan0 disconnect
fi
```

## Verifying Your WiFi Manager

### Check Which Manager Is Active

```bash
# Check if NetworkManager is managing wlan0
nmcli device status

# Output if NetworkManager is active:
# DEVICE  TYPE      STATE      CONNECTION
# wlan0   wifi      connected  YourNetwork

# Check if wpa_supplicant is active
systemctl is-active wpa_supplicant

# Output if wpa_supplicant is active:
# active
```

### Check OVBuddy Detection

```bash
# View wifi-monitor logs
sudo journalctl -u ovbuddy-wifi | grep "WiFi manager detected"

# Should show:
# WiFi manager detected: networkmanager
# or
# WiFi manager detected: wpa_supplicant
```

## NetworkManager Configuration

### List Configured Networks

```bash
# Show all connection profiles
nmcli connection show

# Show only WiFi connections
nmcli connection show | grep wifi
```

### Delete a Network

```bash
# Delete a specific network
sudo nmcli connection delete "NetworkName"

# Example:
sudo nmcli connection delete "MyOldWiFi"
```

### Add a Network

```bash
# Add a new WiFi network
sudo nmcli device wifi connect "SSID" password "password"

# Add a hidden network
sudo nmcli device wifi connect "SSID" password "password" hidden yes
```

### View Network Details

```bash
# Show connection details
nmcli connection show "NetworkName"

# Show WiFi password
sudo nmcli connection show "NetworkName" | grep psk
```

## Troubleshooting

### Force AP Mode Not Working

**Check WiFi manager:**
```bash
ssh pi@ovbuddy.local
sudo journalctl -u ovbuddy-wifi | grep "WiFi manager"
```

**Check if NetworkManager is blocking:**
```bash
nmcli device status
# If wlan0 shows "connected", NetworkManager is managing it
```

**Manually test NetworkManager disconnect:**
```bash
sudo nmcli device disconnect wlan0
sudo nmcli device set wlan0 managed no
```

### Device Reconnects After Force AP

This happens if:
1. NetworkManager is still managing wlan0
2. The force-AP flag wasn't created
3. wifi-monitor didn't detect the flag

**Check flag file:**
```bash
ls -la /tmp/ovbuddy-force-ap
# Should exist after running force-ap-mode.sh
```

**Check wifi-monitor logs:**
```bash
sudo journalctl -u ovbuddy-wifi -b | grep "Force AP"
# Should show: "Force AP mode flag detected"
```

### NetworkManager Not Detected

If OVBuddy doesn't detect NetworkManager:

**Verify NetworkManager is running:**
```bash
systemctl status NetworkManager
```

**Check if nmcli works:**
```bash
nmcli device status
```

**Manually set in wifi-monitor:**
Edit `/home/pi/ovbuddy/wifi-monitor.py` and force detection:
```python
# In main() function, after detect_wifi_manager():
wifi_manager = 'networkmanager'  # Force NetworkManager
```

### AP Mode Doesn't Start

**Check if NetworkManager is still managing wlan0:**
```bash
nmcli device status | grep wlan0
# Should show "unmanaged" when in AP mode
```

**Manually set to unmanaged:**
```bash
sudo nmcli device set wlan0 managed no
sudo systemctl restart ovbuddy-wifi
```

### Can't Reconnect to WiFi After AP Mode

**Check if NetworkManager is managing wlan0:**
```bash
nmcli device status | grep wlan0
# Should show "connected" or "disconnected", not "unmanaged"
```

**Manually re-enable management:**
```bash
sudo nmcli device set wlan0 managed yes
sudo nmcli radio wifi off
sudo nmcli radio wifi on
```

## Switching Between Managers

### Disable NetworkManager, Use wpa_supplicant

```bash
# Stop and disable NetworkManager
sudo systemctl stop NetworkManager
sudo systemctl disable NetworkManager

# Enable and start wpa_supplicant
sudo systemctl enable wpa_supplicant
sudo systemctl start wpa_supplicant

# Reboot
sudo reboot
```

### Enable NetworkManager, Disable wpa_supplicant

```bash
# Stop and disable wpa_supplicant
sudo systemctl stop wpa_supplicant
sudo systemctl disable wpa_supplicant

# Enable and start NetworkManager
sudo systemctl enable NetworkManager
sudo systemctl start NetworkManager

# Reboot
sudo reboot
```

## Testing NetworkManager Support

### Test 1: Detection

```bash
# Restart wifi-monitor and check logs
sudo systemctl restart ovbuddy-wifi
sudo journalctl -u ovbuddy-wifi | tail -20

# Look for: "WiFi manager detected: networkmanager"
```

### Test 2: Force AP Mode

```bash
# Trigger force AP mode
sudo /home/pi/ovbuddy/force-ap-mode.sh

# After reboot, check logs
sudo journalctl -u ovbuddy-wifi -b | grep -A 10 "Force AP"

# Should show:
# - Force AP mode flag detected
# - Setting wlan0 to unmanaged in NetworkManager
# - Switching to Access Point mode
```

### Test 3: Reconnection

```bash
# While in AP mode, connect to AP
# Use web interface to configure WiFi
# Check logs for reconnection

sudo journalctl -u ovbuddy-wifi -f

# Should show:
# - Configured network detected
# - Re-enabling NetworkManager management
# - Switching to WiFi client mode
```

## Files Modified

### Core Changes
- `dist/wifi-monitor.py`
  - Added `detect_wifi_manager()` function
  - Updated `is_configured_wifi_available()` for NetworkManager
  - Updated `switch_to_ap_mode()` to disable NetworkManager
  - Updated `switch_to_client_mode()` to re-enable NetworkManager

- `dist/force-ap-mode.sh`
  - Added NetworkManager detection
  - Uses `nmcli` for NetworkManager, `wpa_cli` for wpa_supplicant

### Documentation
- `NETWORKMANAGER_SUPPORT.md` - This file

## Summary

✅ **Auto-detection**: Automatically detects NetworkManager or wpa_supplicant  
✅ **Transparent operation**: Works the same regardless of WiFi manager  
✅ **Force AP mode**: Works correctly with NetworkManager  
✅ **WiFi reconnection**: Properly re-enables NetworkManager after AP mode  
✅ **Backward compatible**: Still works with wpa_supplicant systems  

The system now works seamlessly on both traditional (wpa_supplicant) and modern (NetworkManager) Raspberry Pi OS installations!

## Quick Commands Reference

### NetworkManager Commands
```bash
# List networks
nmcli connection show

# Delete network
sudo nmcli connection delete "NetworkName"

# Connect to network
sudo nmcli device wifi connect "SSID" password "password"

# Disconnect
sudo nmcli device disconnect wlan0

# Set unmanaged
sudo nmcli device set wlan0 managed no

# Set managed
sudo nmcli device set wlan0 managed yes

# Scan networks
nmcli device wifi list

# Show device status
nmcli device status
```

### wpa_supplicant Commands
```bash
# List networks
sudo wpa_cli -i wlan0 list_networks

# Remove network
sudo wpa_cli -i wlan0 remove_network 0

# Disconnect
sudo wpa_cli -i wlan0 disconnect

# Reconnect
sudo wpa_cli -i wlan0 reconfigure

# Scan networks
sudo iwlist wlan0 scan

# Show status
sudo wpa_cli -i wlan0 status
```

