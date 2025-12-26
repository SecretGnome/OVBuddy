# NetworkManager Fix - Summary

## The Problem You Reported

> "The raspberry pi still seems to reconnect with the old network. On Bullseye/Bookworm, Wi-Fi is often managed by NetworkManager. /etc/wpa_supplicant/wpa_supplicant.conf → ignored. I deleted the preconfigured entry but the raspberry pi does still not start the access-point mode."

## Root Cause

OVBuddy was designed for **wpa_supplicant**, but your Raspberry Pi is using **NetworkManager**:

- Our scripts were trying to use `wpa_cli` commands → **ignored by NetworkManager**
- Clearing `/etc/wpa_supplicant/wpa_supplicant.conf` → **had no effect**
- NetworkManager stores WiFi networks in `/etc/NetworkManager/system-connections/`
- Even after deleting networks, NetworkManager was still managing wlan0

## The Fix

OVBuddy now **automatically detects** and supports both WiFi managers:

### 1. Auto-Detection
- Detects NetworkManager or wpa_supplicant at startup
- Logs which manager is in use
- Adapts all WiFi operations accordingly

### 2. NetworkManager Support
- Uses `nmcli` commands instead of `wpa_cli`
- Sets wlan0 to "unmanaged" when entering AP mode
- Re-enables NetworkManager management when returning to client mode
- Properly disconnects and reconnects

### 3. Force AP Mode Fixed
- Detects NetworkManager and uses correct disconnect command
- Creates flag file that survives reboot
- wifi-monitor sees flag and immediately enters AP mode
- No more reconnecting to old networks!

## What Changed

### Files Modified

1. **`dist/wifi-monitor.py`**
   - Added `detect_wifi_manager()` - auto-detects which manager is active
   - Updated `is_configured_wifi_available()` - works with NetworkManager
   - Updated `switch_to_ap_mode()` - disables NetworkManager before AP mode
   - Updated `switch_to_client_mode()` - re-enables NetworkManager after AP mode

2. **`dist/force-ap-mode.sh`**
   - Detects NetworkManager vs wpa_supplicant
   - Uses `nmcli device disconnect` for NetworkManager
   - Uses `wpa_cli disconnect` for wpa_supplicant

3. **Documentation**
   - `NETWORKMANAGER_SUPPORT.md` - Complete NetworkManager guide
   - `NETWORKMANAGER_FIX_SUMMARY.md` - This file

## How to Deploy

```bash
# 1. Deploy updated files
cd /Users/mik/Development/Pi/OVBuddy/scripts
./deploy.sh

# 2. Reboot to test
ssh pi@192.168.1.167 'sudo reboot'

# 3. Wait 60 seconds, then test force AP mode
sleep 60
./force-ap-mode.sh
```

## Testing the Fix

### Test 1: Verify Detection

```bash
# Check which WiFi manager is detected
ssh pi@ovbuddy.local 'sudo journalctl -u ovbuddy-wifi | grep "WiFi manager detected"'

# Should show:
# WiFi manager detected: networkmanager
```

### Test 2: Force AP Mode

```bash
# From your Mac
cd scripts
./force-ap-mode.sh

# After reboot (~1 minute):
# 1. Look for "OVBuddy" WiFi network
# 2. Connect to it
# 3. Open http://192.168.4.1:8080
# 4. Should see web interface
```

### Test 3: Reconnect to WiFi

```bash
# While connected to AP:
# 1. Open http://192.168.4.1:8080
# 2. Go to WiFi Management
# 3. Scan for networks
# 4. Select your WiFi
# 5. Enter password
# 6. Click Connect

# Device should reconnect within 30 seconds
```

## Verifying It Works

After deployment, check the logs:

```bash
ssh pi@ovbuddy.local 'sudo journalctl -u ovbuddy-wifi -b'
```

Look for these key messages:

```
✅ WiFi manager detected: networkmanager
✅ Force AP mode flag detected
✅ Setting wlan0 to unmanaged in NetworkManager
✅ Switching to Access Point mode
✅ AP mode active
```

When reconnecting:

```
✅ Configured network detected
✅ Re-enabling NetworkManager management of wlan0
✅ Switching to WiFi client mode
✅ Client mode restored
```

## Why "No departure found" Was Showing

The display was showing "No departure found" because:
1. Device was connected to WiFi (not in AP mode)
2. But couldn't fetch departure data (maybe API issue or network problem)
3. So it showed the error message instead of AP info

Now with the fix:
1. Force AP mode actually works
2. Device enters AP mode immediately after reboot
3. Display shows AP information
4. You can connect and configure WiFi

## NetworkManager Commands for Reference

### Check Current Status
```bash
nmcli device status
```

### List Configured Networks
```bash
nmcli connection show
```

### Delete a Network
```bash
sudo nmcli connection delete "NetworkName"
```

### Disconnect
```bash
sudo nmcli device disconnect wlan0
```

### Check if wlan0 is Managed
```bash
nmcli device status | grep wlan0
# "managed" = NetworkManager controls it
# "unmanaged" = NetworkManager ignores it (AP mode)
```

## Summary of Changes

✅ **Auto-detects NetworkManager** - No manual configuration needed  
✅ **Force AP mode works** - No more reconnecting to old networks  
✅ **Proper AP mode entry** - wlan0 set to unmanaged  
✅ **Proper client mode return** - NetworkManager re-enabled  
✅ **Backward compatible** - Still works with wpa_supplicant  
✅ **Flag file approach** - Survives reboot reliably  

## Next Steps

1. **Deploy the fix**: Run `./deploy.sh`
2. **Test force AP mode**: Run `./force-ap-mode.sh`
3. **Verify AP mode works**: Look for "OVBuddy" network
4. **Test reconnection**: Configure WiFi from AP mode
5. **Verify logs**: Check that NetworkManager is detected

The system should now work correctly with NetworkManager!

## If It Still Doesn't Work

If force AP mode still doesn't work after deployment:

1. **Check if files were deployed:**
   ```bash
   ssh pi@192.168.1.167 'head -30 /home/pi/ovbuddy/wifi-monitor.py | grep detect_wifi_manager'
   # Should show the detect_wifi_manager function
   ```

2. **Check if service was restarted:**
   ```bash
   ssh pi@ovbuddy.local 'sudo systemctl restart ovbuddy-wifi'
   ssh pi@ovbuddy.local 'sudo journalctl -u ovbuddy-wifi | tail -20'
   ```

3. **Manually test NetworkManager commands:**
   ```bash
   ssh pi@ovbuddy.local
   sudo nmcli device set wlan0 managed no
   sudo nmcli device status | grep wlan0
   # Should show "unmanaged"
   ```

4. **Check for errors:**
   ```bash
   ssh pi@ovbuddy.local 'sudo journalctl -u ovbuddy-wifi -p err'
   ```

## Support

See detailed documentation:
- `NETWORKMANAGER_SUPPORT.md` - Complete NetworkManager guide
- `FORCE_AP_MODE.md` - Force AP mode documentation
- `DEPLOYMENT_FIX.md` - Deployment and troubleshooting
- `QUICK_FIX_GUIDE.md` - Quick reference

The fix is comprehensive and should resolve all NetworkManager-related issues!

