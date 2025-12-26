# Raspberry Pi OS Bookworm Compatibility Guide

## Overview

This document explains how the OVBuddy SD card setup script works with **Raspberry Pi OS Bookworm** on **Raspberry Pi Zero W**.

## Key Decisions

### ✅ Using Bookworm (Not Bullseye)

**Why Bookworm:**
- Current stable release
- Better long-term support
- Security updates
- Modern tooling

**Bookworm works on Pi Zero W:**
- ✅ Boots successfully (slower than newer Pi models, but functional)
- ✅ Supports headless provisioning
- ✅ `firstrun.sh` mechanism still works
- ✅ `imager_custom` paths present
- ✅ SSH and user setup work correctly

### ⚠️ Pi Zero W Limitations

**Hardware Constraints:**
- **WiFi:** 2.4GHz only (no 5GHz)
- **WPA:** WPA2 only (no WPA3/SAE)
- **Speed:** Single-core ARMv6 (slow but adequate)

## Critical Bookworm-Specific Fixes

### 1. WiFi Configuration for Pi Zero W

**Problem:**
Bookworm defaults assume WPA3 support, but Pi Zero W only supports WPA2.

**Wrong (Will Fail Silently):**
```bash
network={
    ssid="MyNetwork"
    key_mgmt=WPA-PSK SAE    # ❌ SAE = WPA3, not supported
    psk=hash
    ieee80211w=1            # ❌ Can break WPA2
}
```

**Correct (Works on Pi Zero W):**
```bash
network={
    ssid="MyNetwork"
    psk=hash
    key_mgmt=WPA-PSK        # ✅ WPA2 only
}
```

**Implementation:**
- No `SAE` in `key_mgmt`
- No `ieee80211w` parameter
- Simple WPA-PSK only

### 2. Package Installation Pattern

**Problem:**
Installing packages directly in `firstrun.sh` is risky on Bookworm:
- Network might not be fully online
- DNS might not be ready
- Can cause boot hangs

**Wrong (Risky):**
```bash
# In firstrun.sh
apt-get update
apt-get install -y avahi-daemon
```

**Correct (Bookworm-Safe):**
```bash
# In firstrun.sh - create a service, don't install packages
cat > /etc/systemd/system/ovbuddy-postboot.service << 'EOF'
[Unit]
Description=OVBuddy Post-Boot Setup
After=network-online.target
Wants=network-online.target
ConditionPathExists=!/etc/ovbuddy-postboot-done

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 10
ExecStart=/usr/bin/apt-get update -qq
ExecStart=/usr/bin/apt-get install -y avahi-daemon
ExecStart=/bin/systemctl enable avahi-daemon
ExecStart=/bin/systemctl start avahi-daemon
ExecStart=/bin/touch /etc/ovbuddy-postboot-done
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl enable ovbuddy-postboot.service
```

**Benefits:**
- Runs after network is guaranteed online
- Doesn't block first boot
- Can retry if network fails
- Proper systemd dependency handling

### 3. NetworkManager vs wpa_supplicant

**Bookworm Reality:**
- Desktop: Uses NetworkManager
- Lite (headless): Still uses wpa_supplicant
- `imager_custom set_wlan` still works
- Writing `/etc/wpa_supplicant/wpa_supplicant.conf` still works

**Our Approach:**
- Use the `imager_custom` path when available
- Fall back to direct `wpa_supplicant.conf` creation
- Both work on Bookworm Lite

### 4. Image Selection

**Correct Image for Pi Zero W:**
```
Raspberry Pi OS Lite (32-bit) — Bookworm
- Architecture: armhf (32-bit ARM)
- Variant: Lite (no desktop)
- Release: Bookworm (Debian 12)
```

**Don't Use:**
- ❌ `oldstable` (points to Bullseye, but URL structure changed)
- ❌ `legacy` (older kernel, not needed)
- ❌ `arm64` (Pi Zero W is 32-bit only)
- ❌ Desktop variants (too heavy for Pi Zero W)

## Boot Sequence

### First Boot (2-3 minutes)

1. **Kernel loads** from SD card
2. **`firstrun.sh` runs** via `systemd.run`
   - Sets hostname
   - Creates user
   - Configures WiFi (WPA2 only)
   - Enables SSH
   - Creates `ovbuddy-postboot.service`
   - Cleans up itself
3. **Automatic reboot** (via `systemd.run_success_action=reboot`)

### Second Boot (2-3 minutes)

1. **System boots normally**
2. **WiFi connects** (WPA2)
3. **`ovbuddy-postboot.service` runs**
   - Waits for network-online
   - Updates package lists
   - Installs Avahi
   - Enables and starts Avahi
   - Creates flag file to prevent re-runs
4. **mDNS active** - `ovbuddy.local` now works

### Total Time: 5-6 minutes

## Verification

### After Setup, Check:

```bash
# 1. Can ping via .local
ping ovbuddy.local

# 2. Can SSH
ssh pi@ovbuddy.local

# 3. Check Avahi is running
ssh pi@ovbuddy.local 'systemctl status avahi-daemon'

# 4. Check post-boot service ran
ssh pi@ovbuddy.local 'systemctl status ovbuddy-postboot.service'

# 5. Check flag file exists
ssh pi@ovbuddy.local 'ls -la /etc/ovbuddy-postboot-done'
```

## Troubleshooting

### WiFi Not Connecting

**Symptoms:**
- Pi boots but not reachable
- No `.local` resolution
- Can't find on network

**Checks:**
1. **Is it 2.4GHz?** Pi Zero W doesn't support 5GHz
2. **Is it WPA2?** Pi Zero W doesn't support WPA3
3. **Is SSID visible?** Hidden networks need special config
4. **Correct country code?** Must match your location

**Solution:**
```bash
# Connect via serial or keyboard/monitor
# Check WiFi status
sudo systemctl status wpa_supplicant
sudo wpa_cli status

# Check config
cat /etc/wpa_supplicant/wpa_supplicant.conf
```

### Avahi Not Installing

**Symptoms:**
- Can connect via IP but not `.local`
- Second boot seems stuck

**Checks:**
```bash
# Check service status
systemctl status ovbuddy-postboot.service

# Check logs
journalctl -u ovbuddy-postboot.service

# Check network
ping 8.8.8.8
```

**Solution:**
```bash
# Manual install
sudo apt-get update
sudo apt-get install -y avahi-daemon
sudo systemctl enable avahi-daemon
sudo systemctl start avahi-daemon
```

### First Boot Never Completes

**Symptoms:**
- Pi seems to hang on first boot
- Never reboots automatically

**Possible Causes:**
1. Corrupted SD card image
2. Bad power supply (under-voltage)
3. SD card read errors

**Solution:**
1. Re-write SD card
2. Use better power supply (1A minimum)
3. Try different SD card

## Bookworm vs Bullseye Comparison

| Feature | Bullseye | Bookworm | Our Choice |
|---------|----------|----------|------------|
| Release | Debian 11 | Debian 12 | **Bookworm** |
| WiFi | wpa_supplicant | NetworkManager (Desktop) / wpa_supplicant (Lite) | Works |
| WPA3 defaults | No | Yes (but we disable) | Disabled |
| Pi Zero W support | ✅ Good | ✅ Good (with fixes) | ✅ |
| Long-term support | Ending | Active | ✅ |
| Package availability | Older | Current | ✅ |

## Best Practices

### 1. Always Use WPA2 Config
```bash
key_mgmt=WPA-PSK  # No SAE
```

### 2. Never Install Packages in firstrun.sh
```bash
# Create service instead
systemctl enable my-postboot.service
```

### 3. Wait for network-online
```bash
[Unit]
After=network-online.target
Wants=network-online.target
```

### 4. Use Condition Files
```bash
ConditionPathExists=!/etc/setup-done
```

### 5. Test on Actual Hardware
- Emulators don't catch WiFi issues
- Pi Zero W is slow - be patient

## Related Documentation

- `doc/SETUP_SD_CARD_FIXES.md` - All fixes applied
- `doc/SD_CARD_TROUBLESHOOTING.md` - Troubleshooting guide
- `doc/AVAHI_MISSING_FIX.md` - Avahi installation details

## Summary

✅ **Bookworm works on Pi Zero W** with these adjustments:
1. WPA2-only WiFi config (no SAE/ieee80211w)
2. Second-boot systemd service for package installation
3. Proper network-online dependencies
4. Correct image selection (armhf Lite)

The script is now **Bookworm-compatible** and **Pi Zero W-safe**! 🎉


