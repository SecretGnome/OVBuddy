# Force AP Mode - Troubleshooting Guide

## Quick Diagnosis

Run the diagnostic script to check if everything is configured correctly:

```bash
cd scripts
./test-force-ap.sh
```

This will check:
- ✓ Script files exist
- ✓ Passwordless sudo is configured
- ✓ API endpoint works
- ✓ WiFi configuration accessible

## Common Issues

### Issue 1: "Permission Denied" or "sudo: a password is required"

**Symptom:**
- Button click does nothing
- API returns error
- Script fails with permission error

**Cause:** Passwordless sudo not configured

**Fix:**
```bash
cd scripts
./setup-passwordless-sudo.sh
```

**Verify:**
```bash
ssh pi@ovbuddy.local
sudo -n bash /home/pi/ovbuddy/force-ap-mode.sh --help
# Should NOT ask for password
```

### Issue 2: Script Not Found

**Symptom:**
- API returns "Force AP mode script not found"
- 404 or file not found errors

**Cause:** Script not deployed

**Fix:**
```bash
cd scripts
./deploy.sh
```

**Verify:**
```bash
ssh pi@ovbuddy.local
ls -la /home/pi/ovbuddy/force-ap-mode.sh
# Should show the script with execute permissions
```

### Issue 3: Button Click Does Nothing

**Symptom:**
- Click "Force AP Mode" button
- Nothing happens
- No error message

**Possible Causes:**

**A) JavaScript Error**

Check browser console (F12):
```javascript
// Look for errors in console
```

**B) Web Service Not Running**

```bash
ssh pi@ovbuddy.local
sudo systemctl status ovbuddy-web
# Should show "active (running)"
```

**Fix:**
```bash
sudo systemctl restart ovbuddy-web
```

**C) API Endpoint Not Responding**

```bash
ssh pi@ovbuddy.local
curl -X POST http://localhost:8080/api/wifi/force-ap
```

Should return JSON with success/error.

### Issue 4: Device Doesn't Reboot

**Symptom:**
- Script runs but device stays online
- No reboot happens

**Cause:** Reboot command needs passwordless sudo

**Check:**
```bash
ssh pi@ovbuddy.local
sudo -n reboot --help
# Should NOT ask for password
```

**Fix:** Re-run passwordless sudo setup:
```bash
cd scripts
./setup-passwordless-sudo.sh
```

### Issue 5: Device Reboots But No AP Mode

**Symptom:**
- Device reboots successfully
- But doesn't create AP
- Can't find "OVBuddy" network

**Possible Causes:**

**A) WiFi Config Not Cleared**

Check if WiFi was actually cleared:
```bash
# After device comes back up
ssh pi@192.168.x.x  # Use IP if available
cat /etc/wpa_supplicant/wpa_supplicant.conf
```

Should show minimal config with no networks:
```
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=CH

# All networks removed - device will enter AP mode
```

**B) WiFi Monitor Not Running**

```bash
ssh pi@ovbuddy.local
sudo systemctl status ovbuddy-wifi
```

**Fix:**
```bash
sudo systemctl start ovbuddy-wifi
sudo systemctl enable ovbuddy-wifi
```

**C) Still Has WiFi Networks**

Manually clear:
```bash
ssh pi@ovbuddy.local
sudo wpa_cli -i wlan0 list_networks
# Note network IDs

sudo wpa_cli -i wlan0 remove_network 0
sudo wpa_cli -i wlan0 remove_network 1
# ... remove all

sudo wpa_cli -i wlan0 save_config
sudo reboot
```

## Step-by-Step Fix

If Force AP Mode isn't working, follow these steps:

### Step 1: Deploy Latest Files

```bash
cd scripts
./deploy.sh
```

Wait for deployment to complete.

### Step 2: Setup Passwordless Sudo

```bash
cd scripts
./setup-passwordless-sudo.sh
```

This configures the necessary permissions.

### Step 3: Test Configuration

```bash
cd scripts
./test-force-ap.sh
```

Review the output:
- All checks should show ✓ OK
- If any show ✗ FAILED, follow the suggested fix

### Step 4: Test Manually

```bash
ssh pi@ovbuddy.local
sudo -n bash /home/pi/ovbuddy/force-ap-mode.sh
```

This should:
1. Backup WiFi config
2. Clear WiFi networks
3. Show "Rebooting in 3 seconds..."
4. Reboot the device

### Step 5: Verify AP Mode

After reboot (wait 3-4 minutes):

1. **Scan for WiFi networks**
   - Look for "OVBuddy" (or your configured SSID)

2. **Connect to AP**
   - Use password if configured
   - Or connect directly if open

3. **Access Web Interface**
   - Open http://192.168.4.1:8080
   - Should see OVBuddy interface

4. **Check Display**
   - E-ink screen should show AP information
   - SSID, password (if enabled), and IP

## Manual Testing Commands

### Test API Endpoint

```bash
# From your computer
curl -X POST http://ovbuddy.local:8080/api/wifi/force-ap

# Expected response:
{
  "success": true,
  "message": "Clearing WiFi configuration and rebooting...",
  "ap_ssid": "OVBuddy",
  "ap_ip": "192.168.4.1:8080",
  "reboot": true
}
```

### Test Script Directly

```bash
ssh pi@ovbuddy.local

# Test without sudo (should fail)
bash /home/pi/ovbuddy/force-ap-mode.sh
# Error: "This script must be run as root"

# Test with sudo (should work)
sudo -n bash /home/pi/ovbuddy/force-ap-mode.sh
# Should show backup, clear, and reboot messages
```

### Check Passwordless Sudo

```bash
ssh pi@ovbuddy.local

# Test sudo without password
sudo -n echo "test"
# Should print "test" without asking for password

# Test specific command
sudo -n bash /home/pi/ovbuddy/force-ap-mode.sh --help
# Should work without password
```

### Check WiFi Monitor

```bash
ssh pi@ovbuddy.local

# Check service status
sudo systemctl status ovbuddy-wifi

# Check logs
sudo journalctl -u ovbuddy-wifi -n 50

# Restart if needed
sudo systemctl restart ovbuddy-wifi
```

## Logs to Check

### Web Service Logs

```bash
ssh pi@ovbuddy.local
sudo journalctl -u ovbuddy-web -n 50
```

Look for:
- API endpoint calls
- Errors running script
- Permission denied errors

### WiFi Monitor Logs

```bash
sudo journalctl -u ovbuddy-wifi -n 50
```

Look for:
- "Starting in client mode"
- "WiFi disconnected"
- "Switching to Access Point mode"

### System Logs

```bash
sudo journalctl -b -n 100
```

Look for:
- Reboot messages
- Service start/stop
- Permission errors

## Configuration Check

### Verify Sudoers File

```bash
ssh pi@ovbuddy.local
sudo cat /etc/sudoers.d/ovbuddy
```

Should include:
```
# Allow force AP mode script
pi ALL=(ALL) NOPASSWD: /usr/bin/bash /home/pi/ovbuddy/force-ap-mode.sh
pi ALL=(ALL) NOPASSWD: /bin/bash /home/pi/ovbuddy/force-ap-mode.sh
```

### Verify Script Permissions

```bash
ssh pi@ovbuddy.local
ls -la /home/pi/ovbuddy/force-ap-mode.sh
```

Should show:
```
-rwxr-xr-x 1 pi pi 2345 Dec 25 14:30 force-ap-mode.sh
```

### Verify AP Configuration

```bash
ssh pi@ovbuddy.local
cat /home/pi/ovbuddy/config.json | grep -A3 ap_
```

Should show:
```json
"ap_fallback_enabled": true,
"ap_ssid": "OVBuddy",
"ap_password": "",
"display_ap_password": false
```

## Still Not Working?

If you've tried everything above and it still doesn't work:

### 1. Check Browser Console

Open browser console (F12) and look for JavaScript errors when clicking the button.

### 2. Test with curl

```bash
curl -v -X POST http://ovbuddy.local:8080/api/wifi/force-ap
```

Look at the response and any errors.

### 3. Run Script Manually

```bash
ssh pi@ovbuddy.local
cd /home/pi/ovbuddy

# Try running directly
sudo bash force-ap-mode.sh
```

Watch for any errors during execution.

### 4. Check File Contents

```bash
ssh pi@ovbuddy.local
cat /home/pi/ovbuddy/force-ap-mode.sh
```

Verify the script content matches the expected version.

### 5. Enable Debug Mode

Add debug output to the script:

```bash
ssh pi@ovbuddy.local
sudo nano /home/pi/ovbuddy/force-ap-mode.sh

# Add at the top (after #!/bin/bash):
set -x  # Enable debug output
```

Then run again and check output.

## Getting Help

If you still can't get it working, collect this information:

1. **Test script output:**
   ```bash
   ./scripts/test-force-ap.sh > test-output.txt 2>&1
   ```

2. **Service logs:**
   ```bash
   ssh pi@ovbuddy.local 'sudo journalctl -u ovbuddy-web -n 100' > web-logs.txt
   ```

3. **WiFi monitor logs:**
   ```bash
   ssh pi@ovbuddy.local 'sudo journalctl -u ovbuddy-wifi -n 100' > wifi-logs.txt
   ```

4. **Sudoers configuration:**
   ```bash
   ssh pi@ovbuddy.local 'sudo cat /etc/sudoers.d/ovbuddy' > sudoers.txt
   ```

5. **Manual test output:**
   ```bash
   ssh pi@ovbuddy.local 'sudo bash /home/pi/ovbuddy/force-ap-mode.sh' > manual-test.txt 2>&1
   ```

Share these files when asking for help.


