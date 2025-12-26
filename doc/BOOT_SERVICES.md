# Boot Services - Troubleshooting Guide

## Overview

OVBuddy consists of several systemd services that should start automatically on boot:

1. **fix-bonjour.service** - Prepares the system for mDNS (runs first)
2. **avahi-daemon.service** - Provides Bonjour/mDNS functionality
3. **ovbuddy-wifi.service** - Monitors WiFi and provides AP fallback
4. **ovbuddy-web.service** - Web interface
5. **ovbuddy.service** - Display service

## Service Boot Order

```
Boot
  ↓
network-online.target
  ↓
fix-bonjour.service (oneshot)
  ↓
avahi-daemon.service
  ↓
ovbuddy-wifi.service
  ↓
ovbuddy-web.service
ovbuddy.service
```

## Common Boot Issues

### Issue 1: avahi-daemon Not Starting

**Symptoms:**
- Can't access device via `ovbuddy.local` after reboot
- Must use IP address to connect
- `systemctl status avahi-daemon` shows inactive

**Causes:**
1. Service was masked
2. fix-bonjour service failed
3. Network not ready when service tried to start

**Fix:**
```bash
# Run the diagnostic script
cd scripts
./fix-boot-services.sh

# Or manually on the Pi:
ssh pi@ovbuddy.local  # Use IP if .local doesn't work
sudo systemctl unmask avahi-daemon
sudo systemctl enable avahi-daemon
sudo systemctl start avahi-daemon
sudo systemctl status avahi-daemon
```

### Issue 2: ovbuddy-wifi Not Starting

**Symptoms:**
- WiFi monitor not running after boot
- No automatic AP fallback when WiFi disconnected
- `systemctl status ovbuddy-wifi` shows inactive

**Causes:**
1. Service not enabled
2. Network not ready when service tried to start
3. Service file not installed

**Note:** The WiFi monitor should run **all the time**, even when WiFi is connected. It monitors the connection and only switches to AP mode when disconnected for 2+ minutes.

**Fix:**
```bash
# Run the diagnostic script
cd scripts
./fix-boot-services.sh

# Or manually on the Pi:
ssh pi@ovbuddy.local
sudo systemctl enable ovbuddy-wifi
sudo systemctl start ovbuddy-wifi
sudo systemctl status ovbuddy-wifi
```

### Issue 3: Services Start Manually But Not on Boot

**Symptoms:**
- Services work when started manually
- After reboot, services are inactive
- No errors in logs

**Causes:**
1. Services not enabled
2. Network timing issues
3. Service dependencies not met

**Fix:**
```bash
# Check if services are enabled
ssh pi@ovbuddy.local
systemctl is-enabled avahi-daemon
systemctl is-enabled ovbuddy-wifi
systemctl is-enabled ovbuddy
systemctl is-enabled ovbuddy-web

# Enable all services
sudo systemctl enable avahi-daemon
sudo systemctl enable ovbuddy-wifi
sudo systemctl enable ovbuddy
sudo systemctl enable ovbuddy-web

# Reboot and test
sudo reboot
```

## Diagnostic Script

Use the provided diagnostic script to check and fix boot issues:

```bash
cd scripts
./fix-boot-services.sh
```

This script will:
1. Check the status of all services
2. Show recent logs for failed services
3. Apply fixes automatically
4. Verify the fixes worked

## Manual Diagnostics

### Check Service Status

```bash
ssh pi@ovbuddy.local

# Check all OVBuddy services
systemctl status avahi-daemon
systemctl status ovbuddy-wifi
systemctl status ovbuddy-web
systemctl status ovbuddy

# Check if services are enabled for boot
systemctl is-enabled avahi-daemon
systemctl is-enabled ovbuddy-wifi
systemctl is-enabled ovbuddy-web
systemctl is-enabled ovbuddy
```

### Check Service Logs

```bash
# View logs for specific service
sudo journalctl -u avahi-daemon -n 50
sudo journalctl -u ovbuddy-wifi -n 50
sudo journalctl -u ovbuddy-web -n 50
sudo journalctl -u ovbuddy -n 50

# View logs since last boot
sudo journalctl -u avahi-daemon -b
sudo journalctl -u ovbuddy-wifi -b

# Follow logs in real-time
sudo journalctl -u ovbuddy-wifi -f
```

### Check Boot Timeline

```bash
# See when services started during boot
systemd-analyze blame

# See critical chain
systemd-analyze critical-chain

# See critical chain for specific service
systemd-analyze critical-chain ovbuddy-wifi.service
```

## Understanding Service Behavior

### avahi-daemon

**Purpose:** Provides Bonjour/mDNS so you can access the device via `ovbuddy.local`

**Should start:** Always, on every boot

**Dependencies:** 
- Network must be up
- fix-bonjour service must run first

**If not running:**
- Device only accessible via IP address
- Must use `ssh pi@192.168.x.x` instead of `ssh pi@ovbuddy.local`

### ovbuddy-wifi

**Purpose:** Monitors WiFi connection and provides AP fallback

**Should start:** Always, on every boot (even when WiFi is connected)

**Behavior:**
- **When WiFi connected:** Monitors connection every 30 seconds
- **When WiFi disconnected:** Waits 2 minutes, then switches to AP mode
- **In AP mode:** Scans for configured WiFi every 60 seconds
- **When WiFi available:** Automatically switches back to client mode

**Dependencies:**
- Network must be online
- Should start before ovbuddy services

**If not running:**
- No automatic AP fallback
- Must manually configure WiFi if connection lost

### fix-bonjour

**Purpose:** Prepares system for mDNS by cleaning /etc/hosts

**Should start:** On every boot (oneshot service)

**Behavior:**
- Removes .local entries from /etc/hosts
- Ensures avahi-daemon is enabled
- Starts avahi-daemon
- Exits after completion

**If it fails:**
- avahi-daemon might not start
- Bonjour/mDNS might not work

## Recent Changes (Fix Applied)

### What Was Changed

1. **ovbuddy-wifi.service**
   - Changed `After=network.target` to `After=network-online.target`
   - Added `Wants=network-online.target`
   - Increased `TimeoutStartSec` to 60 seconds
   - Ensures network is fully ready before starting

2. **fix-bonjour-persistent.sh**
   - Removed `--no-block` from systemctl commands
   - Added retry logic for avahi-daemon start
   - Increased wait time for service to start
   - Better error reporting

3. **fix-bonjour.service**
   - Added `Before=ovbuddy-wifi.service`
   - Increased `TimeoutStartSec` to 60 seconds
   - Ensures it runs before WiFi monitor

### Why These Changes

**Problem:** Services were trying to start before the network was fully ready.

**Solution:** 
- Wait for `network-online.target` instead of just `network.target`
- Give services more time to start (60 seconds instead of 30)
- Remove non-blocking starts that don't wait for completion
- Add retry logic for critical services

## Testing Boot Behavior

### Test 1: Clean Boot

```bash
# Reboot the device
ssh pi@ovbuddy.local 'sudo reboot'

# Wait 60 seconds

# Check all services
cd scripts
./fix-boot-services.sh
```

**Expected Result:** All services should be active and enabled.

### Test 2: Service Persistence

```bash
# Stop a service
ssh pi@ovbuddy.local 'sudo systemctl stop ovbuddy-wifi'

# Reboot
ssh pi@ovbuddy.local 'sudo reboot'

# Wait 60 seconds

# Check if it started
ssh pi@ovbuddy.local 'systemctl status ovbuddy-wifi'
```

**Expected Result:** Service should be running after reboot.

### Test 3: WiFi Monitor Behavior

```bash
# Connect to Pi
ssh pi@ovbuddy.local

# Check WiFi monitor is running
systemctl status ovbuddy-wifi

# Check logs to see it's monitoring
sudo journalctl -u ovbuddy-wifi -n 20

# Should see messages like:
# "Starting in client mode (WiFi connected)"
# "WiFi is connected, reset disconnect timer"
```

## Redeploying After Fix

To apply the fixes, redeploy:

```bash
cd scripts
./deploy.sh
```

This will:
1. Copy updated service files
2. Copy updated fix-bonjour-persistent.sh
3. Reinstall all services
4. Enable and start all services

Then reboot and test:

```bash
# Reboot via deployment script
./deploy.sh -reboot

# Or manually
ssh pi@ovbuddy.local 'sudo reboot'

# Wait 60 seconds, then test
./fix-boot-services.sh
```

## Support

If services still don't start on boot after applying fixes:

1. **Check logs:**
   ```bash
   ssh pi@ovbuddy.local
   sudo journalctl -b | grep -E "avahi|ovbuddy"
   ```

2. **Check network timing:**
   ```bash
   systemd-analyze critical-chain ovbuddy-wifi.service
   ```

3. **Check for errors:**
   ```bash
   sudo journalctl -p err -b
   ```

4. **Run diagnostic script:**
   ```bash
   cd scripts
   ./fix-boot-services.sh
   ```

5. **Report issue** with:
   - Output of diagnostic script
   - Service logs
   - Boot logs


