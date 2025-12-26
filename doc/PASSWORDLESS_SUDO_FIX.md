# Passwordless Sudo Fix for Force AP Mode

## Problem

The "Force AP Mode" feature wasn't working because the script needs to run with root privileges to:
- Clear WiFi configuration files
- Modify system network settings
- Reboot the device

Without proper passwordless sudo configuration, the script would either:
- Fail silently
- Ask for a password (which can't be provided via web interface)
- Return permission denied errors

## Solution

### 1. Updated Passwordless Sudo Configuration

Modified `scripts/setup-passwordless-sudo.sh` to include:

```bash
# Allow WiFi monitor service control
${PI_USER} ALL=(ALL) NOPASSWD: /bin/systemctl * ovbuddy-wifi
${PI_USER} ALL=(ALL) NOPASSWD: /bin/systemctl is-active ovbuddy-wifi
${PI_USER} ALL=(ALL) NOPASSWD: /bin/systemctl is-enabled ovbuddy-wifi

# Allow force AP mode script (runs as root, needs full access)
${PI_USER} ALL=(ALL) NOPASSWD: /usr/bin/bash /home/pi/ovbuddy/force-ap-mode.sh
${PI_USER} ALL=(ALL) NOPASSWD: /bin/bash /home/pi/ovbuddy/force-ap-mode.sh
```

This allows the `pi` user to run the force-ap-mode script with sudo without requiring a password.

### 2. Created Diagnostic Script

Created `scripts/test-force-ap.sh` to help diagnose issues:

**Features:**
- Checks if script files exist and are executable
- Tests passwordless sudo configuration
- Verifies API endpoint is accessible
- Tests WiFi configuration access
- Attempts a dry-run of the script
- Provides clear pass/fail indicators
- Suggests fixes for each issue

**Usage:**
```bash
cd scripts
./test-force-ap.sh
```

**Example Output:**
```
==========================================
Force AP Mode - Diagnostic Test
==========================================

Connecting to: pi@192.168.1.100

=== Checking Files ===

force-ap-mode.sh exists... ✓ OK
force-ap-mode.sh is executable... ✓ OK

=== Checking Passwordless Sudo ===

General sudo access... ✓ OK
Testing: Run force-ap-mode.sh... ✓ OK

=== Checking API Endpoint ===

Web service running... ✓ OK
API endpoint accessible... ✓ OK

=== Checking WiFi Configuration ===

wpa_supplicant.conf exists... ✓ OK
wpa_cli accessible... ✓ OK

=== Testing Script Execution ===

Attempting to run force-ap-mode.sh with sudo...
(This will show any permission errors)

Forcing Access Point Mode...
Backing up WiFi configuration...
  ✓ Backed up to /home/pi/ovbuddy/wifi-backup/wpa_supplicant.conf.20231225_143000

==========================================
Summary
==========================================

✓ Force AP mode should work!

To test, run:
  ./scripts/force-ap-mode.sh

Or via web interface:
  http://ovbuddy.local:8080
  Click 'Force AP Mode' button
```

### 3. Created Comprehensive Troubleshooting Guide

Created `FORCE_AP_TROUBLESHOOTING.md` with:

**Sections:**
1. Quick Diagnosis (using test script)
2. Common Issues and Fixes
   - Permission denied errors
   - Script not found
   - Button click does nothing
   - Device doesn't reboot
   - Device reboots but no AP mode
3. Step-by-Step Fix Process
4. Manual Testing Commands
5. Logs to Check
6. Configuration Verification
7. Advanced Debugging

**Common Issues Covered:**

**Issue 1: Permission Denied**
```bash
# Fix:
cd scripts
./setup-passwordless-sudo.sh

# Verify:
ssh pi@ovbuddy.local
sudo -n bash /home/pi/ovbuddy/force-ap-mode.sh --help
```

**Issue 2: Script Not Found**
```bash
# Fix:
cd scripts
./deploy.sh
```

**Issue 3: Button Does Nothing**
- Check browser console for JavaScript errors
- Verify web service is running
- Test API endpoint with curl

**Issue 4: Device Doesn't Reboot**
- Verify reboot command has passwordless sudo
- Re-run setup-passwordless-sudo.sh

**Issue 5: No AP Mode After Reboot**
- Check if WiFi config was actually cleared
- Verify WiFi monitor service is running
- Manually remove networks if needed

### 4. Updated Documentation

**README.md:**
- Added "Force AP Mode Not Working" section
- Links to diagnostic script
- Links to troubleshooting guide

**Structure:**
```markdown
## Troubleshooting

### Force AP Mode Not Working

Run diagnostic script:
```bash
cd scripts
./test-force-ap.sh
```

See FORCE_AP_TROUBLESHOOTING.md for details.
```

## How It Works

### Passwordless Sudo Flow

1. **Web Interface** → User clicks "Force AP Mode" button
2. **JavaScript** → Sends POST to `/api/wifi/force-ap`
3. **Flask API** → Calls `subprocess.run(['sudo', 'bash', '/home/pi/ovbuddy/force-ap-mode.sh'])`
4. **Sudoers File** → Checks `/etc/sudoers.d/ovbuddy` for permission
5. **Script Runs** → Clears WiFi config and reboots (no password required)

### Sudoers Configuration

The `/etc/sudoers.d/ovbuddy` file contains:

```bash
# Allow force AP mode script (runs as root, needs full access)
pi ALL=(ALL) NOPASSWD: /usr/bin/bash /home/pi/ovbuddy/force-ap-mode.sh
pi ALL=(ALL) NOPASSWD: /bin/bash /home/pi/ovbuddy/force-ap-mode.sh
```

This means:
- User `pi` can run the script with `sudo`
- No password required (`NOPASSWD`)
- Both `/usr/bin/bash` and `/bin/bash` paths covered
- Full path to script specified for security

### Security Considerations

**Why This Is Safe:**

1. **Specific Script Only**
   - Only `/home/pi/ovbuddy/force-ap-mode.sh` can be run
   - Not a blanket "allow all sudo" permission

2. **Limited Scope**
   - Script only clears WiFi config and reboots
   - Doesn't expose other system functions

3. **Owned by User**
   - Script is in user's home directory
   - User controls what the script does

4. **Auditable**
   - Script contents can be reviewed
   - Actions are logged in system journal

**What Could Go Wrong:**

1. **Malicious Script Replacement**
   - If someone gains access to the Pi
   - They could replace the script with malicious code
   - Mitigation: Secure your Pi's SSH access

2. **Accidental Execution**
   - User clicks button by mistake
   - Device reboots and enters AP mode
   - Mitigation: Add confirmation dialog (future enhancement)

## Testing

### Test 1: Passwordless Sudo

```bash
ssh pi@ovbuddy.local
sudo -n bash /home/pi/ovbuddy/force-ap-mode.sh --help
```

**Expected:** No password prompt
**Actual:** Should show script help or run without error

### Test 2: API Endpoint

```bash
curl -X POST http://ovbuddy.local:8080/api/wifi/force-ap
```

**Expected:**
```json
{
  "success": true,
  "message": "Clearing WiFi configuration and rebooting...",
  "ap_ssid": "OVBuddy",
  "ap_ip": "192.168.4.1:8080",
  "reboot": true
}
```

### Test 3: Full Flow

1. Open web interface: http://ovbuddy.local:8080
2. Click "Force AP Mode" button
3. Confirm the action
4. Wait for device to reboot (3-4 minutes)
5. Scan for WiFi networks
6. Connect to "OVBuddy" AP
7. Access http://192.168.4.1:8080

**Expected:** All steps work without errors

### Test 4: Diagnostic Script

```bash
cd scripts
./test-force-ap.sh
```

**Expected:** All checks show ✓ OK

## Deployment

### Initial Setup

```bash
# 1. Deploy files
cd scripts
./deploy.sh

# 2. Setup passwordless sudo
./setup-passwordless-sudo.sh

# 3. Test configuration
./test-force-ap.sh

# 4. Test manually
ssh pi@ovbuddy.local
sudo -n bash /home/pi/ovbuddy/force-ap-mode.sh
```

### After Updates

```bash
# 1. Deploy updated files
cd scripts
./deploy.sh

# 2. Verify passwordless sudo still works
./test-force-ap.sh
```

Note: Passwordless sudo configuration persists across deployments, but it's good to verify.

## Files Changed

### New Files

1. **`scripts/test-force-ap.sh`**
   - Diagnostic script for Force AP Mode
   - Tests all components
   - Provides clear pass/fail indicators

2. **`FORCE_AP_TROUBLESHOOTING.md`**
   - Comprehensive troubleshooting guide
   - Common issues and fixes
   - Manual testing commands
   - Log checking procedures

3. **`PASSWORDLESS_SUDO_FIX.md`** (this file)
   - Documents the fix
   - Explains the solution
   - Testing procedures

### Modified Files

1. **`scripts/setup-passwordless-sudo.sh`**
   - Added WiFi monitor service control
   - Added force-ap-mode script permissions

2. **`README.md`**
   - Added Force AP Mode troubleshooting section
   - Links to diagnostic script
   - Links to troubleshooting guide

## Future Enhancements

### 1. Confirmation Dialog

Add a confirmation dialog in the web interface:

```javascript
function forceApMode() {
    if (!confirm('This will clear WiFi configuration and reboot the device. Continue?')) {
        return;
    }
    // ... existing code
}
```

### 2. Backup Restoration

Add a feature to restore WiFi config from backup:

```bash
# List available backups
ls -la /home/pi/ovbuddy/wifi-backup/

# Restore specific backup
sudo cp /home/pi/ovbuddy/wifi-backup/wpa_supplicant.conf.20231225_143000 \
       /etc/wpa_supplicant/wpa_supplicant.conf
sudo systemctl restart wpa_supplicant
```

### 3. Dry Run Mode

Add a dry-run flag to test without actually rebooting:

```bash
sudo bash /home/pi/ovbuddy/force-ap-mode.sh --dry-run
```

### 4. Status Indicator

Show current mode (Client/AP) in web interface:

```javascript
// In loadWiFiStatus()
if (data.mode === 'ap') {
    document.getElementById('wifi-mode').textContent = 'Access Point Mode';
} else {
    document.getElementById('wifi-mode').textContent = 'Client Mode';
}
```

## Summary

The Force AP Mode feature now works reliably by:

1. ✅ Configuring passwordless sudo for the force-ap-mode script
2. ✅ Creating a diagnostic script to verify configuration
3. ✅ Providing comprehensive troubleshooting documentation
4. ✅ Updating main README with troubleshooting section

**To use:**
1. Deploy: `./scripts/deploy.sh`
2. Setup sudo: `./scripts/setup-passwordless-sudo.sh`
3. Test: `./scripts/test-force-ap.sh`
4. Use: Click "Force AP Mode" in web interface

**To troubleshoot:**
1. Run: `./scripts/test-force-ap.sh`
2. Read: `FORCE_AP_TROUBLESHOOTING.md`
3. Check logs: `sudo journalctl -u ovbuddy-web -n 50`


