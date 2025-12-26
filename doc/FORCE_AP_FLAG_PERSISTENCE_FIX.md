# Force AP Mode - Flag Persistence Fix

## Critical Issue Discovered

After implementing the auto-connect fix, we discovered a **critical bug** that prevented Force AP mode from working at all.

## The Problem

### What Was Happening

1. User triggers Force AP mode
2. Script creates flag file: `/tmp/ovbuddy-force-ap`
3. Script disables auto-connect
4. Device reboots
5. **During boot, `/tmp` directory is cleared** ❌
6. wifi-monitor starts and checks for flag file
7. **Flag file doesn't exist** (was deleted during boot)
8. wifi-monitor doesn't enter AP mode
9. Device stays disconnected with no AP

### The Root Cause

The flag file was stored in `/tmp/ovbuddy-force-ap`, but **`/tmp` is a temporary filesystem that gets cleared on every reboot**.

From the Linux filesystem hierarchy:
- `/tmp` - Temporary files, **cleared on reboot**
- `/var/lib` - Persistent application state, **survives reboots**

### Why This Wasn't Caught Earlier

The auto-connect fix worked perfectly - WiFi was properly disabled. But the flag file that tells wifi-monitor to enter AP mode was being deleted during the reboot process, before wifi-monitor could read it.

## The Solution

### Change Flag File Location

Move the flag file from `/tmp` to `/var/lib`:

**Before (BROKEN):**
```bash
FORCE_AP_FLAG="/tmp/ovbuddy-force-ap"
```

**After (FIXED):**
```bash
FORCE_AP_FLAG="/var/lib/ovbuddy-force-ap"
```

### Why `/var/lib`?

- **Persistent**: Survives reboots
- **Standard location**: Used for application state files
- **Writable**: Accessible with sudo
- **Appropriate**: Designed for this exact use case

## Timeline Comparison

### Before Fix (BROKEN)

```
Time    Event
----    -----
0:00    Force AP script runs
        - Creates flag: /tmp/ovbuddy-force-ap ✓
        - Disables auto-connect ✓
        - Reboots
----    -----
0:30    Device boots
        - /tmp directory cleared ❌
        - Flag file deleted ❌
----    -----
0:40    wifi-monitor starts
        - Checks for flag: /tmp/ovbuddy-force-ap
        - Flag doesn't exist ❌
        - Sees WiFi disconnected
        - Waits for 2 minutes (normal behavior)
        - No AP mode triggered
----    -----
Result: Device disconnected, no AP mode
```

### After Fix (WORKING)

```
Time    Event
----    -----
0:00    Force AP script runs
        - Creates flag: /var/lib/ovbuddy-force-ap ✓
        - Disables auto-connect ✓
        - Reboots
----    -----
0:30    Device boots
        - /var/lib preserved ✓
        - Flag file still exists ✓
----    -----
0:40    wifi-monitor starts
        - Checks for flag: /var/lib/ovbuddy-force-ap
        - Flag exists ✓
        - Enters AP mode immediately ✓
        - Removes flag file
----    -----
0:50    AP mode active
        - SSID: "OVBuddy"
        - IP: 192.168.4.1
        - Web interface available
----    -----
Result: AP mode working correctly
```

## Files Changed

### 1. `dist/force-ap-mode.sh`

```bash
# Before
FORCE_AP_FLAG="/tmp/ovbuddy-force-ap"

# After
FORCE_AP_FLAG="/var/lib/ovbuddy-force-ap"
```

### 2. `dist/wifi-monitor.py`

```python
# Before
FORCE_AP_FLAG = "/tmp/ovbuddy-force-ap"

# After
FORCE_AP_FLAG = "/var/lib/ovbuddy-force-ap"
```

### 3. `scripts/diagnose-force-ap.sh`

```bash
# Before
if run_remote "[ -f /tmp/ovbuddy-force-ap ] && echo 'exists' || echo 'not found'"

# After
if run_remote "[ -f /var/lib/ovbuddy-force-ap ] && echo 'exists' || echo 'not found'"
```

### 4. Documentation Updates

- `doc/FORCE_AP_MODE.md`
- `doc/FORCE_AP_FIX_AUTOCONNECT.md`
- `doc/FORCE_AP_ROOT_CAUSE_ANALYSIS.md`

All references to `/tmp/ovbuddy-force-ap` updated to `/var/lib/ovbuddy-force-ap`.

## How to Apply

### 1. Deploy Updated Files

```bash
cd scripts
./deploy.sh
```

### 2. Clean Up Old Flag (if exists)

```bash
ssh pi@ovbuddy.local
sudo rm -f /tmp/ovbuddy-force-ap
```

### 3. Test Force AP Mode

```bash
cd scripts
./force-ap-mode.sh
```

Wait ~60 seconds, then look for "OVBuddy" WiFi network.

## Verification

### Check Flag File Location

**Before reboot:**
```bash
ssh pi@ovbuddy.local
ls -la /var/lib/ovbuddy-force-ap
# Should exist after triggering Force AP mode
```

**After reboot:**
```bash
ssh pi@ovbuddy.local
ls -la /var/lib/ovbuddy-force-ap
# Should still exist (until wifi-monitor removes it)
```

### Check wifi-monitor Logs

```bash
ssh pi@ovbuddy.local
sudo journalctl -u ovbuddy-wifi -n 50
```

Look for:
```
Force AP mode flag detected, entering AP mode immediately
Removed force AP flag file
Successfully entered forced AP mode
```

### Verify AP Mode Active

```bash
ssh pi@192.168.4.1  # Connect to AP first
sudo iwconfig wlan0 | grep Mode
# Should show "Mode:Master"
```

## Why This Is Critical

Without this fix:
- ❌ Force AP mode doesn't work at all
- ❌ Flag file disappears during reboot
- ❌ Device stays disconnected
- ❌ No way to access device without physical access

With this fix:
- ✅ Force AP mode works reliably
- ✅ Flag file persists across reboots
- ✅ Device enters AP mode as expected
- ✅ Remote access always possible

## Testing Results

### Test 1: Force AP Mode Entry

**Steps:**
1. Device connected to WiFi
2. Run `./scripts/force-ap-mode.sh`
3. Wait for reboot

**Expected:**
- Flag file created in `/var/lib`
- Auto-connect disabled
- Device reboots
- Flag file still exists after boot
- wifi-monitor detects flag
- AP mode activated

**Result:** ✅ PASS

### Test 2: Flag Persistence

**Steps:**
1. Create flag: `sudo touch /var/lib/ovbuddy-force-ap`
2. Reboot device
3. Check if flag still exists

**Expected:**
- Flag exists before reboot
- Flag exists after reboot

**Result:** ✅ PASS

### Test 3: Diagnostic Script

**Steps:**
1. Create flag file
2. Run `./scripts/diagnose-force-ap.sh`

**Expected:**
- Script detects flag file
- Shows warning that Force AP was requested

**Result:** ✅ PASS

## Lessons Learned

### 1. Temporary vs Persistent Storage

**Temporary (`/tmp`):**
- Cleared on reboot
- Use for: cache, temporary processing files
- **Don't use for**: state that needs to survive reboots

**Persistent (`/var/lib`):**
- Survives reboots
- Use for: application state, flags, persistent data
- **Use for**: anything that needs to persist across reboots

### 2. Test Across Reboots

When implementing features that involve reboots:
- Always test the complete flow including reboot
- Verify that state persists as expected
- Check logs after reboot to confirm behavior

### 3. Filesystem Hierarchy Matters

Understanding Linux filesystem hierarchy is critical:
- `/tmp` - Temporary, cleared on boot
- `/var/tmp` - Temporary, but preserved across reboots
- `/var/lib` - Application state
- `/var/run` or `/run` - Runtime state, cleared on boot

Choose the right location based on persistence requirements.

## Related Issues

This fix addresses the issue where Force AP mode appeared to work (WiFi was disabled) but AP mode never activated because the flag file was deleted during boot.

## Summary

**Problem:** Flag file stored in `/tmp` was deleted during reboot, preventing AP mode activation.

**Solution:** Move flag file to `/var/lib` which persists across reboots.

**Impact:** Force AP mode now works reliably and consistently.

**Lesson:** Always use persistent storage for state that needs to survive reboots.

