# SD Card Setup (Raspberry Pi Imager)

OVBuddy is designed to run on **Raspberry Pi OS Lite** and be deployed via `./scripts/deploy.sh`.

## What you need

- Raspberry Pi (tested on **Pi Zero W 1.1**)
- MicroSD card (8GB+)
- A Mac/PC with **Raspberry Pi Imager**

## Steps (GUI)

1. Open **Raspberry Pi Imager**
2. **Device**: select your Raspberry Pi model (e.g. *Raspberry Pi Zero W*)
3. **OS**: choose **Raspberry Pi OS Lite (32-bit)**
4. **Storage**: select your SD card
5. Click the **gear** (OS customization / settings) and configure:
   - **Hostname**: `ovbuddy` (or your preferred name)
   - **Enable SSH**: on
   - **Username / password**: choose a username/password (default user is often `pi` depending on OS version)
   - **Configure WiFi**: SSID + password (**2.4GHz** for Pi Zero W), set WiFi country
6. Write the image to the SD card
7. Insert SD card into the Pi and power it on
8. Wait 2–5 minutes for first boot and initial setup

## Next steps

- Find the device on your network:
  - Try: `ping ovbuddy.local`
  - Or run: `./scripts/find-pi.sh`
- Deploy OVBuddy:
  - Follow the root `README.md` (create `.env`, then run `./scripts/deploy.sh`)


