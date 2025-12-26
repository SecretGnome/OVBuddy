# Force AP Mode Auto-Reconnect Fix

## Date
December 26, 2025

## Problems Fixed

### Problem 1: Auto-Reconnect Issue
Force AP mode was not working reliably. After triggering Force AP mode and rebooting, the Raspberry Pi would reconnect to known WiFi networks instead of entering Access Point mode.

### Problem 2: Flag File Persistence (CRITICAL)
After fixing the auto-reconnect issue, we discovered the flag file was stored in `/tmp` which gets cleared on reboot. This meant the wifi-monitor service never received the signal to enter AP mode.

## Root Causes

### Root Cause 1: Auto-Reconnect Not Disabled
The `force-ap-mode.sh` script only **disconnected** from WiFi but didn't **disable auto-connect**. After reboot, NetworkManager or wpa_supplicant would automatically reconnect to known networks before the wifi-monitor service could detect the force AP flag and enter AP mode.

### Root Cause 2: Flag File in Temporary Directory (CRITICAL)
The flag file was stored in `/tmp/ovbuddy-force-ap`, but **`/tmp` is cleared during boot**. The flag file was deleted before wifi-monitor could read it, so AP mode was never triggered.

## Solutions

### Solution 1: Disable Auto-Connect Before Reboot
Modified the Force AP mode workflow to disable auto-connect before rebooting:

1. **For NetworkManager:**
   - Disable auto-connect for all WiFi connections
   - Set wlan0 to unmanaged temporarily

2. **For wpa_supplicant:**
   - Disable all configured networks
   - Save configuration

3. **When returning to client mode:**
   - Re-enable auto-connect for all connections
   - Re-enable all networks

### Solution 2: Move Flag File to Persistent Location (CRITICAL)
Changed flag file location from `/tmp` to `/var/lib`:

**Before (BROKEN):**
```bash
FORCE_AP_FLAG="/tmp/ovbuddy-force-ap"  # Cleared on reboot!
```

**After (FIXED):**
```bash
FORCE_AP_FLAG="/var/lib/ovbuddy-force-ap"  # Persists across reboots
```

This ensures the flag file survives the reboot and wifi-monitor can detect it.

## Files Changed

### Modified Files

1. **`dist/force-ap-mode.sh`**
   - Added logic to disable auto-connect for NetworkManager connections
   - Added logic to disable all networks for wpa_supplicant
   - Set wlan0 to unmanaged for NetworkManager
   - **Changed flag file location from `/tmp` to `/var/lib`** (CRITICAL)
   - These changes prevent auto-reconnection after reboot

2. **`dist/wifi-monitor.py`**
   - Added logic to re-enable auto-connect when switching back to client mode (NetworkManager)
   - Added logic to re-enable all networks when switching back to client mode (wpa_supplicant)
   - **Changed flag file location from `/tmp` to `/var/lib`** (CRITICAL)
   - Ensures WiFi works normally after exiting AP mode

3. **`scripts/diagnose-force-ap.sh`**
   - Updated to check for flag file in `/var/lib` instead of `/tmp`

4. **`README.md`**
   - Updated Force AP troubleshooting section
   - Added reference to new diagnostic script
   - Added explanation of common auto-reconnect issue

### New Files

4. **`scripts/diagnose-force-ap.sh`**
   - New diagnostic script to identify Force AP issues
   - Detects WiFi manager type (NetworkManager vs wpa_supplicant)
   - Shows current WiFi connection status
   - Lists configured networks and their auto-connect status
   - Checks force AP flag status
   - Checks wifi-monitor service status
   - Checks if device is in AP mode
   - Provides actionable recommendations

5. **`doc/FORCE_AP_FIX_AUTOCONNECT.md`**
   - Comprehensive technical documentation
   - Explains the auto-connect problem and solution
   - Updated with new flag file location
   - Provides verification commands
   - Includes troubleshooting steps

6. **`doc/FORCE_AP_ROOT_CAUSE_ANALYSIS.md`**
   - Detailed root cause analysis
   - Timeline diagrams showing broken vs fixed behavior
   - Updated with new flag file location
   - Technical details about NetworkManager and wpa_supplicant
   - Lessons learned

7. **`doc/FORCE_AP_FLAG_PERSISTENCE_FIX.md`** (NEW)
   - Documents the critical flag persistence issue
   - Explains why `/tmp` doesn't work
   - Details the move to `/var/lib`
   - Timeline comparison before and after fix
   - Testing results and verification

8. **`doc/FORCE_AP_MODE.md`**
   - Updated flag file location references

## How to Apply

### 1. Deploy Updated Files
```bash
cd scripts
./deploy.sh
```

### 2. Test Force AP Mode
```bash
# Via script
cd scripts
./force-ap-mode.sh

# Or via web interface
# Click "Force AP Mode" button
```

### 3. Verify with Diagnostics
```bash
cd scripts
./diagnose-force-ap.sh
```

## Expected Behavior

### Before Fixes (BROKEN)
1. Force AP mode triggered
2. Flag created in `/tmp` ❌
3. Device disconnects and reboots
4. `/tmp` cleared during boot, flag deleted ❌
5. Device auto-reconnects to known WiFi ❌
6. wifi-monitor starts, no flag found ❌
7. Stays in client mode (wrong)

### After Auto-Connect Fix Only (STILL BROKEN)
1. Force AP mode triggered
2. Flag created in `/tmp` ❌
3. Device disables auto-connect ✓
4. Device reboots
5. `/tmp` cleared during boot, flag deleted ❌
6. Device does NOT auto-reconnect ✓
7. wifi-monitor starts, no flag found ❌
8. Device stays disconnected, no AP mode ❌

### After Both Fixes (WORKING)
1. Force AP mode triggered
2. Flag created in `/var/lib` ✓
3. Device disables auto-connect ✓
4. Device reboots
5. `/var/lib` preserved, flag persists ✓
6. Device does NOT auto-reconnect ✓
7. wifi-monitor starts, flag found ✓
8. wifi-monitor enters AP mode immediately ✓
9. AP mode active (correct) ✓

## Testing

### Test Case 1: Force AP Mode Entry
1. Device connected to WiFi
2. Trigger Force AP mode
3. Wait for reboot (~60 seconds)
4. **Expected:** Device creates AP "OVBuddy"
5. **Expected:** Can connect to AP and access http://192.168.4.1:8080

### Test Case 2: Return to Client Mode
1. Device in AP mode
2. Connect to AP
3. Configure WiFi via web interface
4. **Expected:** Device switches to client mode
5. **Expected:** Device connects to WiFi
6. **Expected:** Auto-connect re-enabled for future reboots

### Test Case 3: Diagnostics
1. Run `./scripts/diagnose-force-ap.sh`
2. **Expected:** Shows current state accurately
3. **Expected:** Provides helpful recommendations

## Verification Commands

### Check Auto-Connect Status (NetworkManager)
```bash
ssh pi@ovbuddy.local
nmcli -f NAME,AUTOCONNECT connection show
```

### Check Network Status (wpa_supplicant)
```bash
ssh pi@ovbuddy.local
sudo wpa_cli -i wlan0 list_networks
```

### Check If In AP Mode
```bash
ssh pi@ovbuddy.local
sudo iwconfig wlan0 | grep Mode
# Should show "Mode:Master" when in AP mode
```

## Compatibility

- ✅ NetworkManager (Raspberry Pi OS Bookworm)
- ✅ wpa_supplicant (Raspberry Pi OS Bullseye and earlier)
- ✅ Raspberry Pi Zero W
- ✅ Raspberry Pi 3/4/5

## Breaking Changes

None. The changes are backward compatible and improve reliability.

## Known Issues

None.

## Future Improvements

- Add web interface indicator showing auto-connect status
- Add option to temporarily disable auto-connect without entering AP mode
- Add scheduled AP mode (e.g., enter AP mode at specific times)

## Documentation

- **Flag Persistence Fix:** `doc/FORCE_AP_FLAG_PERSISTENCE_FIX.md` (CRITICAL - Read this first!)
- **Auto-Connect Fix:** `doc/FORCE_AP_FIX_AUTOCONNECT.md`
- **Root Cause Analysis:** `doc/FORCE_AP_ROOT_CAUSE_ANALYSIS.md`
- **Troubleshooting:** `doc/FORCE_AP_TROUBLESHOOTING.md`
- **General Force AP Info:** `doc/FORCE_AP_MODE.md`

## Related Issues

This fix resolves two critical issues:
1. Auto-reconnection to known WiFi networks preventing AP mode
2. Flag file deletion during boot preventing AP mode activation

