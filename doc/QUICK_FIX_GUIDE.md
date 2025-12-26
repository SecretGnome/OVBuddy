# Quick Fix Guide - Force AP Mode & Avahi Issues

## TL;DR - What Changed

### Problem 1: Force AP Mode Reconnects to WiFi
**Old behavior:** Cleared WiFi config → reboot → wait 2 minutes → maybe enter AP mode → often reconnects instead  
**New behavior:** Create flag file → reboot → immediately enter AP mode → works every time

### Problem 2: Avahi-Daemon Not Starting on Boot
**Old behavior:** Services start in wrong order → avahi-daemon doesn't start → ovbuddy.local unreachable  
**New behavior:** Proper service dependencies → avahi-daemon starts first → everything works

## How to Fix (5 Minutes)

### Option 1: Automated (Recommended)

```bash
# 1. Deploy updated files
cd /Users/mik/Development/Pi/OVBuddy/scripts
./deploy.sh

# 2. SSH to Pi and reinstall services
ssh pi@192.168.1.167
cd /home/pi/ovbuddy
sudo ./install-service.sh

# 3. Reboot to test
sudo reboot

# 4. Wait 60 seconds and verify
# (from your Mac)
ping ovbuddy.local
```

### Option 2: Manual Steps

If automated deployment doesn't work:

```bash
# 1. Copy files manually
scp dist/wifi-monitor.py pi@192.168.1.167:/home/pi/ovbuddy/
scp dist/force-ap-mode.sh pi@192.168.1.167:/home/pi/ovbuddy/
scp dist/fix-bonjour.service pi@192.168.1.167:/home/pi/ovbuddy/
scp dist/ovbuddy-wifi.service pi@192.168.1.167:/home/pi/ovbuddy/

# 2. SSH to Pi
ssh pi@192.168.1.167

# 3. Make scripts executable
cd /home/pi/ovbuddy
chmod +x force-ap-mode.sh wifi-monitor.py

# 4. Install service files
sudo cp fix-bonjour.service /etc/systemd/system/
sudo cp ovbuddy-wifi.service /etc/systemd/system/

# 5. Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart fix-bonjour
sudo systemctl restart avahi-daemon
sudo systemctl restart ovbuddy-wifi

# 6. Verify
sudo systemctl status avahi-daemon
sudo systemctl status ovbuddy-wifi
```

## Test Force AP Mode

### Via Web Interface
1. Open `http://192.168.1.167:8080` (or `http://ovbuddy.local:8080`)
2. Click "Force AP Mode" button
3. Confirm
4. Wait ~1 minute
5. Look for WiFi network "OVBuddy"
6. Connect and open `http://192.168.4.1:8080`

### Via Command Line
```bash
# From your Mac
cd /Users/mik/Development/Pi/OVBuddy/scripts
./force-ap-mode.sh

# Or directly on Pi
ssh pi@192.168.1.167
sudo /home/pi/ovbuddy/force-ap-mode.sh
```

## Verify Everything Works

Run this one-liner to check all services:

```bash
ssh pi@ovbuddy.local 'sudo systemctl status avahi-daemon ovbuddy-wifi ovbuddy ovbuddy-web --no-pager'
```

All should show `active (running)`.

## What If It Still Doesn't Work?

### Force AP Mode Not Working

```bash
# Check if new script was deployed
ssh pi@192.168.1.167 'head -10 /home/pi/ovbuddy/force-ap-mode.sh'

# Should show: "# This script forces the device into AP mode by creating a flag file"
# If it says "clearing WiFi configuration", old script is still there

# Check wifi-monitor logs
ssh pi@192.168.1.167 'sudo journalctl -u ovbuddy-wifi -n 50'

# Look for: "Force AP mode flag detected"
```

### Avahi-Daemon Not Starting

```bash
# Check if it's enabled
ssh pi@ovbuddy.local 'sudo systemctl is-enabled avahi-daemon'

# If not enabled:
ssh pi@ovbuddy.local 'sudo systemctl unmask avahi-daemon'
ssh pi@ovbuddy.local 'sudo systemctl enable avahi-daemon'
ssh pi@ovbuddy.local 'sudo systemctl start avahi-daemon'

# Check fix-bonjour service
ssh pi@ovbuddy.local 'sudo journalctl -u fix-bonjour -b'
```

## Key Changes Made

### 1. `wifi-monitor.py`
- Added flag file check on startup: `/tmp/ovbuddy-force-ap`
- If flag exists, immediately enter AP mode
- No 2-minute wait, no WiFi config clearing

### 2. `force-ap-mode.sh`
- Creates flag file: `touch /tmp/ovbuddy-force-ap`
- Disconnects WiFi: `wpa_cli -i wlan0 disconnect`
- Reboots: `reboot`
- WiFi config preserved

### 3. `fix-bonjour.service`
- Added proper dependencies: `After=dbus.service`
- Added restart policy: `Restart=on-failure`
- Ensures avahi-daemon starts before OVBuddy services

### 4. `ovbuddy-wifi.service`
- Added dependencies: `After=fix-bonjour.service avahi-daemon.service`
- Added startup delay: `ExecStartPre=/bin/sleep 5`
- Ensures network is ready before starting

## Timeline Comparison

### Old Force AP Mode
```
0:00 - Trigger force AP
0:03 - Reboot
0:30 - Boot complete
0:30 - wpa_supplicant reconnects to WiFi (BUG!)
2:30 - Maybe detect no WiFi
3:00 - Maybe enter AP mode
Result: Often fails, 3-4 minutes when it works
```

### New Force AP Mode
```
0:00 - Trigger force AP (create flag)
0:03 - Reboot
0:30 - Boot complete
0:35 - wifi-monitor sees flag
0:36 - Enter AP mode immediately
1:00 - AP fully active
Result: Always works, ~1 minute
```

## Need More Help?

See detailed guides:
- `DEPLOYMENT_FIX.md` - Full deployment instructions
- `FORCE_AP_MODE.md` - Force AP mode documentation
- `AVAHI_FIX.md` - Avahi-daemon troubleshooting

Or collect logs:
```bash
ssh pi@ovbuddy.local 'sudo journalctl -b > /tmp/logs.txt'
scp pi@ovbuddy.local:/tmp/logs.txt .
```

