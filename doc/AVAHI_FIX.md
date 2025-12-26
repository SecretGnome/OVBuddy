# Avahi-Daemon Boot Fix

## Problem

The avahi-daemon service (which provides Bonjour/mDNS functionality) was not starting automatically when the Raspberry Pi boots up. This caused `ovbuddy.local` hostname resolution to fail after reboots, requiring manual intervention to start the service.

## Root Causes

1. **avahi-daemon not enabled**: The service may not have been enabled to start on boot
2. **avahi-daemon masked**: The service may have been masked (prevented from starting)
3. **Timing issues**: The fix-bonjour service may have been running before network was fully ready
4. **Missing dependencies**: avahi-daemon package may not have been installed

## Solution

### Changes Made

#### 1. Enhanced `fix-bonjour-persistent.sh`

The script now:
- Checks if avahi-daemon is installed, installs it if missing
- Unmasks avahi-daemon (in case it was masked)
- Explicitly enables avahi-daemon to start on boot
- Adds better logging to journald for debugging
- Implements retry logic for starting avahi-daemon
- Returns proper exit codes for systemd

**Key improvements:**
```bash
# Unmask avahi-daemon in case it was masked
systemctl unmask avahi-daemon 2>/dev/null || true

# Ensure avahi-daemon is enabled to start on boot
systemctl enable avahi-daemon 2>/dev/null || true

# Use --no-block to prevent systemctl deadlocks
# This is CRITICAL for preventing web interface timeouts
systemctl start avahi-daemon --no-block 2>/dev/null || true
systemctl restart avahi-daemon --no-block 2>/dev/null || true
```

#### 2. Updated `fix-bonjour.service`

The systemd service file now:
- Adds `Wants=avahi-daemon.service` to ensure avahi-daemon is started
- Adds `After=systemd-resolved.service` for better timing
- Increases timeout to 30 seconds to allow for slower boots
- Better documentation in comments

**Key changes:**
```ini
[Unit]
After=network-online.target systemd-resolved.service
Wants=network-online.target
Wants=avahi-daemon.service

[Service]
TimeoutStartSec=30
```

#### 3. Updated `install-fix-bonjour.sh`

The installation script now:
- Checks if avahi-daemon is installed before installing the service
- Installs avahi-daemon and avahi-utils if missing
- Unmasks and enables avahi-daemon during installation
- Provides better feedback about what's being done

#### 4. New `ensure-avahi-enabled.sh` Script

A standalone script that can be run on the Pi to:
- Install avahi-daemon if missing
- Unmask avahi-daemon
- Enable avahi-daemon to start on boot
- Start avahi-daemon if not running
- Verify the configuration
- Check for .local entries in /etc/hosts that might interfere

**Usage on Pi:**
```bash
sudo ./ensure-avahi-enabled.sh
```

#### 5. New `fix-avahi-boot.sh` Script

A deployment script that can be run from your Mac to:
- Deploy the ensure-avahi-enabled.sh script to the Pi
- Run it remotely
- Update the fix-bonjour service with the new version
- Verify the fix was applied correctly

**Usage from Mac:**
```bash
cd scripts
./fix-avahi-boot.sh
```

#### 6. Enhanced `diagnose-bonjour.sh`

The diagnostic script now:
- Checks if avahi-daemon is masked
- Shows recent avahi-daemon logs
- Provides actionable fix commands

## How to Apply the Fix

### Option 1: Automated Fix from Mac (Recommended)

```bash
cd scripts
./fix-avahi-boot.sh
```

This will deploy and apply all fixes automatically.

### Option 2: Manual Fix on Pi

```bash
# SSH to the Pi (use IP if .local doesn't work)
ssh pi@[pi-ip-address]

# Run the ensure script
sudo ./ensure-avahi-enabled.sh

# Verify
sudo systemctl status avahi-daemon
sudo systemctl is-enabled avahi-daemon
```

### Option 3: Deploy with deploy.sh

The next time you run `./deploy.sh`, it will automatically install the updated fix-bonjour service with the new logic.

## Verification

After applying the fix:

1. **Check current status:**
   ```bash
   ssh pi@ovbuddy.local 'sudo systemctl status avahi-daemon'
   ssh pi@ovbuddy.local 'sudo systemctl is-enabled avahi-daemon'
   ```

2. **Test with reboot:**
   ```bash
   # Reboot the Pi
   ssh pi@ovbuddy.local 'sudo reboot'
   
   # Wait 60 seconds for boot
   sleep 60
   
   # Test mDNS resolution
   ping ovbuddy.local
   ssh pi@ovbuddy.local
   ```

3. **Check logs after reboot:**
   ```bash
   ssh pi@ovbuddy.local 'sudo journalctl -u avahi-daemon -u fix-bonjour -b'
   ```

## What to Look For

### Successful Boot

After a successful boot, you should see:
- `avahi-daemon` is **enabled** and **active**
- `fix-bonjour` service ran successfully
- No errors in journald logs
- `ovbuddy.local` resolves correctly

```bash
$ ssh pi@ovbuddy.local 'sudo systemctl status avahi-daemon'
● avahi-daemon.service - Avahi mDNS/DNS-SD Stack
   Loaded: loaded (/lib/systemd/system/avahi-daemon.service; enabled)
   Active: active (running) since ...
```

### Failed Boot

If avahi-daemon still doesn't start:
1. Check if it's masked: `systemctl is-masked avahi-daemon`
2. Check for errors: `journalctl -u avahi-daemon -n 50`
3. Check network timing: `journalctl -u fix-bonjour -n 50`
4. Manually run: `sudo systemctl start avahi-daemon` and check for errors

## Technical Details

### Why avahi-daemon Might Not Start

1. **Masked service**: A previous troubleshooting attempt may have masked the service
2. **Not enabled**: The service was never enabled to start on boot
3. **Network timing**: The service tried to start before network was ready
4. **Conflicting entries**: /etc/hosts entries interfered with mDNS
5. **Missing package**: avahi-daemon was not installed

### How the Fix Works

1. **fix-bonjour.service** runs early in the boot process
2. It cleans /etc/hosts to remove .local entries
3. It ensures avahi-daemon is unmasked and enabled
4. It starts avahi-daemon with retry logic
5. systemd's `Wants=avahi-daemon.service` ensures avahi-daemon is pulled in
6. The service logs everything to journald for debugging

### Service Dependencies

```
network-online.target
        ↓
systemd-resolved.service
        ↓
fix-bonjour.service
        ↓
avahi-daemon.service
```

## Files Modified

- `dist/fix-bonjour-persistent.sh` - Enhanced with unmask, enable, and retry logic
- `dist/fix-bonjour.service` - Updated dependencies and timeout
- `dist/install-fix-bonjour.sh` - Added avahi-daemon installation check
- `dist/diagnose-bonjour.sh` - Added masked check and log display
- `dist/ensure-avahi-enabled.sh` - New standalone fix script
- `scripts/fix-avahi-boot.sh` - New deployment script
- `README.md` - Added troubleshooting section

## Important: Non-Blocking Service Management

The `fix-bonjour-persistent.sh` script uses `systemctl --no-block` when starting/restarting avahi-daemon. This is **critical** to prevent systemd deadlocks where:

1. The fix-bonjour service tries to start avahi-daemon
2. Other services (like ovbuddy) try to stop/start
3. systemctl commands hang waiting for each other

**Without `--no-block`:**
- Web interface shutdown/restart commands may timeout
- systemctl commands can hang for 10+ seconds
- Boot process may be delayed

**With `--no-block`:**
- Commands return immediately
- No deadlocks or timeouts
- Boot process is fast
- Web interface commands work reliably

## Future Improvements

If issues persist, consider:
1. Adding a systemd timer to periodically check avahi-daemon status
2. Creating a watchdog service to restart avahi-daemon if it dies
3. Adding more detailed logging about network state during boot
4. Implementing a fallback to static IP if mDNS fails

## References

- [systemd service dependencies](https://www.freedesktop.org/software/systemd/man/systemd.service.html)
- [Avahi documentation](https://www.avahi.org/)
- [mDNS/Bonjour protocol](https://en.wikipedia.org/wiki/Multicast_DNS)

