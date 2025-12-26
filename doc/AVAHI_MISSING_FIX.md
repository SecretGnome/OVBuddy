# Avahi Missing Fix

## Problem

The SD card setup script (`setup-sd-card.sh`) creates a bootable Raspberry Pi OS image with WiFi and SSH configured, but **does not install Avahi** (the mDNS/Bonjour service). This causes the following issue:

1. ✅ Pi boots successfully
2. ✅ WiFi connects
3. ✅ SSH is enabled
4. ❌ `.local` hostname resolution doesn't work
5. ❌ Cannot connect via `ovbuddy.local`

## Root Cause

Raspberry Pi OS Lite (the minimal image we use) **does not include Avahi by default**. The `firstrun.sh` script created by `setup-sd-card.sh` configures the hostname, WiFi, and SSH, but doesn't install any additional packages.

Without Avahi:
- The Pi has a hostname (`ovbuddy`)
- The Pi is on the network
- BUT the hostname is not advertised via mDNS/Bonjour
- macOS and other devices cannot resolve `ovbuddy.local`

## Solution

### Immediate Workaround (For Existing Installations)

If your Pi is already set up but not reachable via `.local`:

1. **Find the Pi's IP address** using one of these methods:
   - Check your router's admin page for a device named "ovbuddy"
   - Run the Pi finder script: `./scripts/find-pi.sh`
   - Use `arp-scan`: `sudo arp-scan --localnet | grep -i raspberry`
   - Use `nmap`: `nmap -sn 192.168.1.0/24 | grep -B 2 Raspberry`

2. **Connect via IP and install Avahi**:
   ```bash
   # Connect via IP
   ssh pi@<IP_ADDRESS>
   
   # Install Avahi
   sudo apt-get update
   sudo apt-get install -y avahi-daemon
   
   # Enable and start it
   sudo systemctl enable avahi-daemon
   sudo systemctl start avahi-daemon
   
   # Exit and test
   exit
   ping ovbuddy.local
   ```

3. **Or run the deploy script** (which now installs Avahi automatically):
   ```bash
   # Update setup.env with the IP address temporarily
   PI_HOST=<IP_ADDRESS>
   
   # Run deploy
   cd scripts
   ./deploy.sh
   
   # After deploy completes, change back to .local
   PI_HOST=ovbuddy.local
   ```

### Permanent Fix (Implemented)

The `deploy.sh` script has been updated to automatically install Avahi if it's not present:

```bash
# Check if avahi-daemon is installed
AVAHI_INSTALLED=$(dpkg -l | grep -q avahi-daemon && echo 'true' || echo 'false')

# Install if missing
if [ "$AVAHI_INSTALLED" != "true" ]; then
    sudo apt-get update -qq
    sudo apt-get install -y avahi-daemon
fi

# Enable and start
sudo systemctl enable avahi-daemon
sudo systemctl start avahi-daemon
```

This fix is now part of the "Fixing Bonjour/mDNS setup" section of the deploy script.

### Enhancement: Avahi in `firstrun.sh` (IMPLEMENTED)

**Status: ✅ IMPLEMENTED**

The `setup-sd-card.sh` script now includes Avahi installation in the `firstrun.sh` script. This makes the Pi immediately reachable via `.local` after first boot.

**Implementation:**

Added to the `firstrun.sh` script after WiFi configuration:

```bash
# Install and enable avahi-daemon for mDNS/.local hostname resolution
echo "Installing avahi-daemon for mDNS support..."
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y avahi-daemon
systemctl enable avahi-daemon
systemctl start avahi-daemon
echo "✓ avahi-daemon installed and enabled"
```

**Benefits:**
- ✅ Pi is immediately reachable via `.local` hostname
- ✅ Better out-of-box experience
- ✅ No need to find IP address
- ✅ Can deploy directly to `ovbuddy.local`

**Trade-offs:**
- First boot takes ~1-2 minutes longer (for package installation)
- Requires WiFi to be working during first boot
- If WiFi fails, Avahi installation will also fail (but won't break the boot)

**Note:** The `deploy.sh` script still checks for and installs Avahi if missing, so older SD cards or manual setups will still work.

## Testing

After the fix is applied (either manually or via deploy script):

1. **Test mDNS resolution from Mac:**
   ```bash
   ping ovbuddy.local
   dns-sd -G v4 ovbuddy.local
   ```

2. **Test SSH connection:**
   ```bash
   ssh pi@ovbuddy.local
   ```

3. **Verify Avahi is running on Pi:**
   ```bash
   ssh pi@ovbuddy.local
   systemctl status avahi-daemon
   ```

4. **Check Avahi is advertising the hostname:**
   ```bash
   avahi-browse -a -t
   ```

## Related Documentation

- `doc/SD_CARD_TROUBLESHOOTING.md` - Comprehensive troubleshooting guide
- `doc/AVAHI_FIX.md` - Original Avahi configuration fixes
- `doc/ZEROCONF_INSTALLATION.md` - Zeroconf/mDNS background information

## Impact

This fix affects:
- ✅ `scripts/deploy.sh` - Now installs Avahi automatically
- ✅ `scripts/find-pi.sh` - New script to help locate Pi on network
- ⏳ `scripts/setup-sd-card.sh` - Could be enhanced to include Avahi in firstrun.sh (future)

## Verification

To verify the fix is working:

1. Set up a fresh SD card using `setup-sd-card.sh`
2. Boot the Pi (will NOT be reachable via `.local` yet)
3. Find the IP using `./scripts/find-pi.sh` or router admin page
4. Update `setup.env` with the IP address
5. Run `./scripts/deploy.sh`
6. After deploy completes, verify `ping ovbuddy.local` works
7. Update `setup.env` back to `ovbuddy.local`

## Timeline

- **2025-12-26**: Issue discovered - Pi not reachable via `.local` after SD card setup
- **2025-12-26**: Root cause identified - Avahi not installed on Raspberry Pi OS Lite
- **2025-12-26**: Fix implemented in `deploy.sh` to auto-install Avahi
- **2025-12-26**: Created `find-pi.sh` helper script
- **2025-12-26**: Created troubleshooting documentation

## Lessons Learned

1. **Raspberry Pi OS Lite is minimal** - Don't assume common services are installed
2. **Test the full user flow** - We tested the SD card creation but not the actual connection
3. **mDNS requires Avahi** - The hostname alone is not enough for `.local` resolution
4. **Provide fallback options** - The `find-pi.sh` script helps when `.local` doesn't work
5. **Document assumptions** - Make it clear what's included and what's not

## Future Considerations

1. Consider adding Avahi to `firstrun.sh` for better out-of-box experience
2. Add a check in `deploy.sh` to verify `.local` resolution is working
3. Consider creating a "first-time setup" script that handles the IP → `.local` transition
4. Add LED blink patterns to indicate different boot stages (including Avahi installation)

