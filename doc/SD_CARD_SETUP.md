# SD card setup

This project ships a macOS-friendly helper to create a Raspberry Pi OS Lite SD card for OVBuddy.

## Method A (recommended): helper script

```bash
cd scripts
./setup-sd-card.sh
```

## Optional: `setup.env` (non-interactive defaults)

`scripts/setup-sd-card.sh` will automatically load `setup.env` from the project root if present.

```bash
cp setup.env.example setup.env
# edit setup.env
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

Example:

```bash
cd scripts
./setup-sd-card.sh --method 1 --disk disk2 --yes
```

## First boot expectations

The SD setup script provisions first-boot configuration and then performs an automatic reboot. Allow ~5–6 minutes total before expecting:
- SSH reachable
- `HOSTNAME.local` to resolve (Avahi/mDNS is installed post-boot)

Notes:
- Pi Zero W is **2.4GHz-only**.
- If `.local` doesn’t resolve yet, use [`scripts/find-pi.sh`](../scripts/find-pi.sh) to locate the IP.

## Method B: Raspberry Pi Imager (manual)

1. Install/launch Raspberry Pi Imager.
2. Choose your device (e.g. Raspberry Pi Zero W).
3. Choose OS: Raspberry Pi OS Lite (32-bit).
4. Set OS customization:
   - Hostname, username/password
   - Enable SSH
   - Configure WiFi (2.4GHz for Pi Zero W), WiFi country
5. Write the SD card, boot the Pi, then continue with [`doc/DEPLOYMENT.md`](DEPLOYMENT.md).
