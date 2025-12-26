# SD Card / First Boot Troubleshooting

## The Pi doesn’t show up on the network

- Confirm your WiFi is **2.4GHz** (Pi Zero W cannot join 5GHz-only networks).
- Double-check **SSID/password** and **WiFi country** in Raspberry Pi Imager settings.
- First boot can take a few minutes; wait **2–5 minutes** after powering on.
- Run the finder script:

```bash
./scripts/find-pi.sh
```

## `ovbuddy.local` doesn’t resolve

- Bonjour/mDNS sometimes takes time to appear after first boot.
- Use your router’s DHCP list to find the Pi’s IP address, then try `ssh user@<ip>`.

## SSH login fails

- Re-check the username/password you configured in Raspberry Pi Imager.
- If you have local console access (monitor/keyboard): run `passwd` to reset the password.

## The Pi doesn’t boot (only red LED / no activity)

- Reflash the SD card with Raspberry Pi Imager.
- Try a different SD card and/or power supply.


