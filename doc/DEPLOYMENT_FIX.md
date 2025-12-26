# Deployment Fix for Force AP Mode and Avahi Issues

## Issues Fixed

1. **Force AP Mode Not Working**: Device reconnects to WiFi after reboot instead of entering AP mode
2. **Avahi-Daemon Not Starting**: The avahi-daemon service doesn't start reliably on boot, causing `ovbuddy.local` to be unreachable

## Root Causes

### Force AP Mode Issue
The previous implementation cleared WiFi configuration and rebooted, but:
- `wpa_supplicant` and `dhcpcd` services auto-start on boot
- They may restore or reconnect to WiFi before wifi-monitor can detect the cleared config
- The 2-minute disconnect threshold meant waiting too long even when no networks were configured

### Avahi-Daemon Issue
The avahi-daemon service wasn't starting reliably because:
- Service dependencies weren't properly ordered
- wifi-monitor was starting before avahi-daemon was ready
- No delay to ensure network was fully initialized

## Solutions Implemented

### 1. Force AP Mode - Flag File Approach

**New Behavior:**
- Creates a flag file `/tmp/ovbuddy-force-ap` before rebooting
- On boot, `wifi-monitor.py` checks for this flag
- If flag exists, immediately enters AP mode (no 2-minute wait)
- Flag is removed after entering AP mode
- WiFi configuration is preserved for easy reconnection

**Files Modified:**
- `dist/force-ap-mode.sh` - Creates flag file instead of clearing WiFi config
- `dist/wifi-monitor.py` - Checks for flag file on startup
- `FORCE_AP_MODE.md` - Updated documentation

**Benefits:**
- Much faster: ~1 minute instead of 3-4 minutes
- More reliable: No race conditions with wpa_supplicant
- Preserves WiFi config: Easy to reconnect later
- No waiting: Immediate AP mode entry

### 2. Avahi-Daemon Boot Reliability

**New Behavior:**
- `fix-bonjour.service` runs before wifi-monitor and other OVBuddy services
- Proper service dependencies ensure correct boot order
- 5-second delay before starting wifi-monitor to ensure network is ready
- Restart on failure for fix-bonjour service

**Files Modified:**
- `dist/fix-bonjour.service` - Updated dependencies and added restart policy
- `dist/ovbuddy-wifi.service` - Added dependencies and 5-second startup delay

**Service Boot Order:**
```
1. network-online.target
2. dbus.service
3. systemd-resolved.service
4. fix-bonjour.service (cleans /etc/hosts, enables avahi-daemon)
5. avahi-daemon.service (mDNS/Bonjour)
6. ovbuddy-wifi.service (WiFi monitor, waits 5 seconds)
7. ovbuddy.service (main display service)
8. ovbuddy-web.service (web interface)
```

## How to Deploy the Fix

### Step 1: Deploy Updated Files

From your Mac:

```bash
cd /Users/mik/Development/Pi/OVBuddy/scripts
./deploy.sh
```

This will copy all updated files to the Pi.

### Step 2: Reinstall Services

SSH to the Pi and reinstall the services:

```bash
ssh pi@192.168.1.167
cd /home/pi/ovbuddy
sudo ./install-service.sh
```

This will:
- Stop all OVBuddy services
- Install updated service files
- Reload systemd daemon
- Restart all services

### Step 3: Verify Avahi-Daemon

Check that avahi-daemon is enabled and running:

```bash
sudo systemctl status avahi-daemon
sudo systemctl is-enabled avahi-daemon
```

Should show:
- Status: `active (running)`
- Enabled: `enabled`

### Step 4: Test Force AP Mode

Test the force AP mode functionality:

```bash
# From your Mac
cd /Users/mik/Development/Pi/OVBuddy/scripts
./force-ap-mode.sh
```

Or via web interface:
1. Open `http://192.168.1.167:8080`
2. Scroll to WiFi Management section
3. Click "Force AP Mode" button
4. Confirm the action

**Expected behavior:**
1. Device reboots (takes ~30 seconds)
2. WiFi monitor detects flag file
3. Enters AP mode immediately (~30 seconds after boot)
4. Total time: ~1 minute
5. Look for WiFi network "OVBuddy" (or your configured SSID)

### Step 5: Test Reconnection

After testing AP mode, reconnect to your WiFi:

1. Connect to the AP (OVBuddy)
2. Open `http://192.168.4.1:8080`
3. Go to WiFi Management section
4. Scan for networks
5. Select your WiFi network
6. Enter password
7. Click "Connect"
8. Device should reconnect to your WiFi within 30 seconds

### Step 6: Verify Boot Reliability

Test that everything works after a reboot:

```bash
ssh pi@192.168.1.167 'sudo reboot'

# Wait 60 seconds
sleep 60

# Test mDNS resolution
ping ovbuddy.local

# Test SSH
ssh pi@ovbuddy.local

# Check services
ssh pi@ovbuddy.local 'sudo systemctl status avahi-daemon ovbuddy-wifi ovbuddy ovbuddy-web'
```

## Troubleshooting

### Force AP Mode Still Not Working

**Check if flag file is created:**
```bash
ssh pi@192.168.1.167
sudo ls -la /tmp/ovbuddy-force-ap
```

**Check wifi-monitor logs:**
```bash
sudo journalctl -u ovbuddy-wifi -b
```

Look for:
- "Force AP mode flag detected"
- "Entering AP mode immediately"

**Manually test flag file:**
```bash
# Create flag file
sudo touch /tmp/ovbuddy-force-ap

# Restart wifi-monitor
sudo systemctl restart ovbuddy-wifi

# Check logs
sudo journalctl -u ovbuddy-wifi -n 50
```

### Avahi-Daemon Still Not Starting

**Check if masked:**
```bash
ssh pi@ovbuddy.local
sudo systemctl is-masked avahi-daemon
```

If masked, unmask it:
```bash
sudo systemctl unmask avahi-daemon
sudo systemctl enable avahi-daemon
sudo systemctl start avahi-daemon
```

**Check fix-bonjour service:**
```bash
sudo systemctl status fix-bonjour
sudo journalctl -u fix-bonjour -b
```

**Check service dependencies:**
```bash
systemctl list-dependencies fix-bonjour
systemctl list-dependencies avahi-daemon
```

**Manually run fix script:**
```bash
sudo /usr/local/bin/fix-bonjour-persistent.sh
```

### Services Not Starting in Correct Order

**Check service dependencies:**
```bash
systemctl show ovbuddy-wifi | grep -E "After|Before|Wants"
systemctl show fix-bonjour | grep -E "After|Before|Wants"
```

**View boot timeline:**
```bash
systemd-analyze critical-chain ovbuddy-wifi.service
systemd-analyze critical-chain avahi-daemon.service
```

**Check for failed services:**
```bash
systemctl --failed
```

### WiFi Monitor Starts Too Early

If wifi-monitor starts before network is ready:

**Increase startup delay in service file:**

Edit `/etc/systemd/system/ovbuddy-wifi.service`:
```ini
[Service]
ExecStartPre=/bin/sleep 10  # Increase from 5 to 10 seconds
```

Then reload:
```bash
sudo systemctl daemon-reload
sudo systemctl restart ovbuddy-wifi
```

## Verification Checklist

After deployment, verify:

- [ ] `avahi-daemon` is enabled: `systemctl is-enabled avahi-daemon`
- [ ] `avahi-daemon` is running: `systemctl is-active avahi-daemon`
- [ ] `ovbuddy.local` resolves: `ping ovbuddy.local`
- [ ] `fix-bonjour.service` is enabled: `systemctl is-enabled fix-bonjour`
- [ ] `ovbuddy-wifi.service` is running: `systemctl is-active ovbuddy-wifi`
- [ ] Force AP mode creates flag: Check `/tmp/ovbuddy-force-ap` after triggering
- [ ] AP mode works: Device enters AP mode within 1 minute of reboot
- [ ] WiFi reconnection works: Can reconnect to WiFi from AP mode
- [ ] Services survive reboot: All services start correctly after reboot

## Quick Reference Commands

**Check all OVBuddy services:**
```bash
ssh pi@ovbuddy.local 'sudo systemctl status ovbuddy ovbuddy-web ovbuddy-wifi fix-bonjour avahi-daemon'
```

**View all logs:**
```bash
ssh pi@ovbuddy.local 'sudo journalctl -u ovbuddy -u ovbuddy-web -u ovbuddy-wifi -u fix-bonjour -u avahi-daemon -b'
```

**Force AP mode (command line):**
```bash
ssh pi@ovbuddy.local 'sudo /home/pi/ovbuddy/force-ap-mode.sh'
```

**Restart all services:**
```bash
ssh pi@ovbuddy.local 'sudo systemctl restart fix-bonjour avahi-daemon ovbuddy-wifi ovbuddy ovbuddy-web'
```

**Check boot time:**
```bash
ssh pi@ovbuddy.local 'systemd-analyze'
ssh pi@ovbuddy.local 'systemd-analyze blame | head -20'
```

## Files Changed

### Modified Files
- `dist/force-ap-mode.sh` - Flag file approach
- `dist/wifi-monitor.py` - Check flag on boot
- `dist/fix-bonjour.service` - Better dependencies and restart policy
- `dist/ovbuddy-wifi.service` - Dependencies and startup delay
- `FORCE_AP_MODE.md` - Updated documentation

### New Files
- `DEPLOYMENT_FIX.md` - This file

## Next Steps

1. Deploy the changes using `./deploy.sh`
2. Reinstall services using `sudo ./install-service.sh`
3. Test force AP mode
4. Verify avahi-daemon starts on boot
5. Test complete reboot cycle
6. Monitor logs for any issues

## Support

If issues persist after following this guide:

1. Collect logs:
   ```bash
   ssh pi@ovbuddy.local 'sudo journalctl -b > /tmp/boot-logs.txt'
   scp pi@ovbuddy.local:/tmp/boot-logs.txt .
   ```

2. Check service status:
   ```bash
   ssh pi@ovbuddy.local 'systemctl status --all > /tmp/service-status.txt'
   scp pi@ovbuddy.local:/tmp/service-status.txt .
   ```

3. Review the logs and service status for errors

## Summary

These changes make the OVBuddy system more reliable:

- **Force AP Mode**: Now works consistently using a flag file approach
- **Avahi-Daemon**: Starts reliably on boot with proper service dependencies
- **Boot Order**: Services start in the correct order with appropriate delays
- **Faster**: AP mode activates in ~1 minute instead of 3-4 minutes
- **Preserved Config**: WiFi settings are maintained for easy reconnection

The system should now be much more robust and easier to troubleshoot.

