# Quick Start Troubleshooting

## Issue: Pi Not Reachable at `ovbuddy.local` After SD Card Setup

### TL;DR

**UPDATE:** As of the latest version, the SD card setup now installs Avahi automatically during first boot. If you're still having issues, it might be:
1. First boot not complete (wait 4-5 minutes instead of 2-3)
2. WiFi connection failed (Avahi needs WiFi to install)
3. Using an old SD card image (recreate with latest `setup-sd-card.sh`)

### Step-by-Step Fix

1. **Find the Pi's IP address:**
   ```bash
   cd scripts
   ./find-pi.sh
   ```
   
   If that doesn't work, check your router's admin page for "ovbuddy".

2. **Update `setup.env` with the IP:**
   ```bash
   # Edit setup.env
   PI_HOST=192.168.1.xxx  # Replace with actual IP
   PI_USER=pi
   PI_PASSWORD=r33b00T!   # Or whatever you set
   ```

3. **Deploy (this installs Avahi):**
   ```bash
   cd scripts
   ./deploy.sh
   ```

4. **Change back to `.local`:**
   ```bash
   # Edit setup.env again
   PI_HOST=ovbuddy.local
   ```

5. **Verify it works:**
   ```bash
   ping ovbuddy.local
   ssh pi@ovbuddy.local
   ```

### Why This Happens

- Raspberry Pi OS Lite is minimal
- Doesn't include Avahi by default
- Avahi is needed for `.local` hostname resolution
- The `deploy.sh` script now auto-installs it

### Alternative: Manual Avahi Installation

If you can SSH via IP but don't want to run full deploy:

```bash
ssh pi@<IP_ADDRESS>
sudo apt-get update
sudo apt-get install -y avahi-daemon
sudo systemctl enable avahi-daemon
sudo systemctl start avahi-daemon
exit

# Now test
ping ovbuddy.local
```

### Common Issues

#### Issue: Can't find IP address
- **Wait longer**: First boot takes 3-4 minutes (includes auto-reboot)
- **Check WiFi**: Verify SSID/password in `setup.env`
- **2.4GHz only**: Pi Zero W doesn't support 5GHz WiFi
- **Country code**: Must be correct (e.g., `CH` for Switzerland)

#### Issue: SSH connection refused
- Pi is still booting - wait another minute
- SSH might not be enabled - re-run `setup-sd-card.sh`

#### Issue: SSH authentication failed
- Check password in `setup.env`
- See [SSH_PASSWORD_FIX.md](SSH_PASSWORD_FIX.md)

#### Issue: Pi found but still no `.local` resolution after deploy
- Flush DNS cache on Mac:
  ```bash
  sudo dscacheutil -flushcache
  sudo killall -HUP mDNSResponder
  ```
- Reboot the Pi:
  ```bash
  ssh pi@<IP_ADDRESS>
  sudo reboot
  ```

### Tools to Find Pi

#### Built-in macOS (no install needed)
```bash
# Method 1: DNS service discovery
dns-sd -B _ssh._tcp

# Method 2: Ping broadcast (sometimes works)
ping -c 1 raspberrypi.local
```

#### With Homebrew tools
```bash
# Install tools
brew install arp-scan nmap

# Method 1: ARP scan (fastest, most reliable)
sudo arp-scan --localnet | grep -i "raspberry\|b8:27:eb\|dc:a6:32"

# Method 2: Nmap scan (slower but thorough)
nmap -sn 192.168.1.0/24 | grep -B 2 "Raspberry"
```

### LED Indicators

Watch the Pi's LEDs to diagnose boot issues:

| LED Pattern | Meaning | Action |
|-------------|---------|--------|
| Red on, green blinking | Normal boot | Wait for boot to complete |
| Only red LED | Not booting | Check SD card, re-write image |
| Both LEDs flashing | Under-voltage | Use better power supply (1A+) |
| 4 green blinks | SD card error | Re-write SD card |
| 7 green blinks | Kernel not found | Re-write SD card |

### Quick Reference

```bash
# 1. Setup SD card
cd scripts
./setup-sd-card.sh

# 2. Find Pi (after 3-4 minutes)
./find-pi.sh

# 3. Update setup.env with IP
nano ../setup.env  # or use your editor

# 4. Deploy (installs Avahi)
./deploy.sh

# 5. Update setup.env to use .local
nano ../setup.env  # Change PI_HOST back to ovbuddy.local

# 6. Test
ping ovbuddy.local
```

### Related Documentation

- [SD_CARD_TROUBLESHOOTING.md](SD_CARD_TROUBLESHOOTING.md) - Comprehensive SD card issues
- [AVAHI_MISSING_FIX.md](AVAHI_MISSING_FIX.md) - Technical details about the Avahi fix
- [SSH_PASSWORD_FIX.md](SSH_PASSWORD_FIX.md) - SSH authentication issues
- [WIFI_SETUP.md](../WIFI_SETUP.md) - WiFi connection problems

### Still Stuck?

1. **Verify SD card was written correctly:**
   - Re-insert SD card into your computer
   - Check if `bootfs` partition is readable
   - Look for `firstrun.sh` in the boot partition

2. **Try a different power supply:**
   - Needs at least 1A (1000mA)
   - Micro USB cable should be good quality

3. **Check WiFi network:**
   - Must be 2.4GHz (not 5GHz)
   - SSID must be visible (not hidden)
   - Password must be correct

4. **Start over:**
   ```bash
   cd scripts
   ./setup-sd-card.sh
   ```
   
   Double-check all settings before confirming.

### Success Checklist

- [ ] SD card created successfully
- [ ] Pi powered on for 3-4 minutes
- [ ] Found Pi's IP address
- [ ] Can SSH via IP: `ssh pi@<IP>`
- [ ] Ran `./deploy.sh` successfully
- [ ] Can ping `.local`: `ping ovbuddy.local`
- [ ] Can SSH via `.local`: `ssh pi@ovbuddy.local`
- [ ] Web interface accessible: `http://ovbuddy.local:8080`

Once all checked, you're good to go! 🎉

