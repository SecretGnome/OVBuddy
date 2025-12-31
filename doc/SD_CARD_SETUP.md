# SD card setup

This project ships a macOS-friendly helper to create a Raspberry Pi OS SD card for OVBuddy. Supports both Raspberry Pi Zero W and Raspberry Pi 4, with Lite and Full OS variants.

## Method A (recommended): helper script

```bash
cd scripts
./setup-sd-card.sh
```

The script will prompt you to select:
- **Pi Model**: Raspberry Pi Zero W or Raspberry Pi 4
- **OS Variant**: Lite (minimal) or Full (with desktop environment)
- **Architecture**: For Pi 4 Lite, choose 32-bit or 64-bit (Pi Zero W is 32-bit only, Pi 4 Full defaults to 64-bit)

## Optional: `.env` (non-interactive defaults)

`scripts/setup-sd-card.sh` will automatically load `.env` from the project root if present.

```bash
cp env.example .env
# edit .env
```

Variables:
- `WIFI_SSID`, `WIFI_PASSWORD`, `WIFI_COUNTRY`
- `HOSTNAME` (default `ovbuddy`)
- `USERNAME` (default `pi`)
- `USER_PASSWORD`

## Automation flags

- `--method <1|2>`: 1 = automated image write, 2 = manual Raspberry Pi Imager instructions
- `--disk <diskN>`: target disk (macOS `diskutil` identifier, e.g. `disk2`)
- `--yes`: skip confirmations (requires `--disk` for safety)
- `--pi-model <zero|4>`: Raspberry Pi model (zero = Pi Zero W, 4 = Pi 4) [default: zero]
- `--os-variant <lite|full>`: OS variant [default: lite]

Examples:

```bash
# Automated setup for Pi Zero W with Lite OS
cd scripts
./setup-sd-card.sh --method 1 --disk disk2 --yes --pi-model zero --os-variant lite

# Automated setup for Pi 4 with Full OS (64-bit)
./setup-sd-card.sh --method 1 --disk disk2 --yes --pi-model 4 --os-variant full
```

## First boot expectations

The SD setup script provisions first-boot configuration and then performs an automatic reboot. Allow ~5–6 minutes total before expecting:
- SSH reachable
- `HOSTNAME.local` to resolve (Avahi/mDNS is installed post-boot)

Notes:
- Pi Zero W is **2.4GHz-only** (Pi 4 supports 5GHz WiFi).
- If `.local` doesn't resolve yet, use [`scripts/find-pi.sh`](../scripts/find-pi.sh) to locate the IP.
- Pi Zero W uses 32-bit images only (armhf).
- Pi 4 can use 32-bit or 64-bit images (armhf or arm64).

## Method B: Raspberry Pi Imager (manual)

1. Install/launch Raspberry Pi Imager.
2. Choose your device:
   - Raspberry Pi Zero W (for Pi Zero W)
   - Raspberry Pi 4 (for Pi 4)
3. Choose OS:
   - **Lite**: Raspberry Pi OS Lite (32-bit or 64-bit for Pi 4)
   - **Full**: Raspberry Pi OS (32-bit or 64-bit for Pi 4)
4. Set OS customization:
   - Hostname, username/password
   - Enable SSH
   - Configure WiFi (2.4GHz for Pi Zero W, both bands for Pi 4), WiFi country
5. Write the SD card, boot the Pi, then continue with [`doc/DEPLOYMENT.md`](DEPLOYMENT.md).
