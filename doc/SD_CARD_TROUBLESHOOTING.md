# SD Card Setup Troubleshooting Guide

## Pi Not Reachable at `ovbuddy.local`

If your Raspberry Pi is not reachable after the initial setup, follow these troubleshooting steps:

### 1. Check Timing (Most Common Issue)

The first boot takes **2-3 minutes** to complete the initial setup and automatic reboot. After the reboot, wait an additional **30-60 seconds** for all services to start.

**Total wait time: 3-4 minutes from first power-on**

### 2. Try Direct IP Connection

If `.local` hostname resolution isn't working, you can find the Pi's IP address:

#### Option A: Check your router's admin page
- Look for a device named `ovbuddy` in the connected devices list
- Note its IP address

#### Option B: Scan your network
```bash
# Install nmap if you don't have it
brew install nmap

# Scan your local network (adjust the IP range for your network)
nmap -sn 192.168.1.0/24 | grep -B 2 "Raspberry Pi"
```

#### Option C: Use arp-scan
```bash
# Install arp-scan if you don't have it
brew install arp-scan

# Scan your network
sudo arp-scan --localnet | grep -i "raspberry\|b8:27:eb"
```

Once you have the IP address, try connecting:
```bash
ssh pi@<IP_ADDRESS>
```

### 3. Check mDNS/Avahi Service

If you can connect via IP but not via `.local` hostname, the Avahi service might not be installed or running.

Connect via IP and check:
```bash
# Check if avahi-daemon is installed
dpkg -l | grep avahi-daemon

# Check if it's running
systemctl status avahi-daemon

# If not installed, install it
sudo apt-get update
sudo apt-get install -y avahi-daemon

# Enable and start it
sudo systemctl enable avahi-daemon
sudo systemctl start avahi-daemon
```

### 4. Check WiFi Connection

The Pi might not have connected to your WiFi network. Common causes:

#### Wrong WiFi Password
- Double-check the password in `setup.env`
- Special characters might need escaping

#### Wrong WiFi Country Code
- Must match your actual location (e.g., `US`, `GB`, `CH`)
- Some channels might be blocked if the country code is wrong

#### 5GHz Network
- Raspberry Pi Zero W only supports **2.4GHz WiFi**
- If your SSID is 5GHz only, the Pi won't connect
- Use a 2.4GHz network or enable 2.4GHz on your dual-band router

#### Hidden SSID
- The current setup doesn't support hidden SSIDs
- Make your network visible temporarily during setup

### 5. Check via Serial Console (Advanced)

If you have a USB-to-TTL serial adapter, you can connect to the Pi's serial console to see boot messages and diagnose issues.

### 6. Check the SD Card

If nothing works, the SD card might not have been written correctly:

1. Re-insert the SD card into your computer
2. Check if the `bootfs` partition is readable
3. Verify that `firstrun.sh` exists in the boot partition
4. Check that `cmdline.txt` contains the `systemd.run=/boot/firstrun.sh` parameter

### 7. Common Issues and Solutions

#### Issue: Pi boots but no network activity
**Solution**: Check the WiFi credentials in `setup.env` and re-run the setup

#### Issue: Green LED blinks in a pattern
**Solution**: This indicates a boot error. Common patterns:
- 4 blinks: SD card not found or corrupted
- 7 blinks: Kernel image not found
- 8 blinks: SDRAM not recognized

#### Issue: Only red LED is on, no green LED
**Solution**: The Pi is powered but not booting. Try:
1. Re-seat the SD card
2. Try a different power supply (needs at least 1A)
3. Re-write the SD card

#### Issue: Both LEDs flash rapidly
**Solution**: Under-voltage detected. Use a better power supply.

### 8. Start Fresh

If all else fails, re-run the setup:

```bash
cd scripts
./setup-sd-card.sh
```

Make sure to:
1. Verify the WiFi password in `setup.env`
2. Confirm the WiFi country code is correct
3. Ensure your WiFi network is 2.4GHz
4. Wait the full 3-4 minutes after first boot

## Avahi Installation Status

**UPDATE (2025-12-26): ✅ FIXED**

The `setup-sd-card.sh` script now automatically installs Avahi during first boot. This means:

1. ✅ The Pi will boot and connect to WiFi
2. ✅ SSH will be enabled
3. ✅ Avahi will be installed automatically
4. ✅ `.local` hostname resolution should work immediately

### First Boot Timing

With Avahi installation included:
- First boot now takes **4-5 minutes** (instead of 2-3)
- This includes WiFi connection, Avahi installation, and automatic reboot
- Wait the full time before trying to connect

### If `.local` Still Doesn't Work

If you've waited 5+ minutes and `.local` still doesn't resolve:

**Option 1: Find IP and connect**
```bash
cd scripts
./find-pi.sh
```

**Option 2: Manually install Avahi** (if using old SD card image)
```bash
# Connect via IP
ssh pi@<IP_ADDRESS>

# Install Avahi
sudo apt-get update
sudo apt-get install -y avahi-daemon
sudo systemctl enable avahi-daemon
sudo systemctl start avahi-daemon

# Now ovbuddy.local should work
```

**Option 3: Recreate SD card** (recommended)
```bash
cd scripts
./setup-sd-card.sh  # Uses latest version with Avahi
```

### Verification

To check if Avahi was installed during first boot:

```bash
ssh pi@ovbuddy.local  # or via IP
systemctl status avahi-daemon
```

Should show "active (running)".

