# Troubleshooting

## Can’t reach `ovbuddy.local`

Common causes:
- the Pi hasn’t finished first boot yet (give it a few minutes)
- mDNS isn’t working on your network/client yet

Actions:

```bash
cd scripts
./find-pi.sh
```

If you have an IP, set `PI_HOST` in `.env` to the IP and deploy anyway; deployment installs/repairs Avahi.

On macOS, you can also flush mDNS/DNS cache:

```bash
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
```

## Can’t SSH

Run the diagnostic helper:

```bash
cd scripts
./test-ssh.sh
```

## Can’t access the web UI

- Check URL: `http://<host-or-ip>:8080`
- Check the service:

```bash
ssh <user>@<host-or-ip>
sudo systemctl status ovbuddy-web
sudo journalctl -u ovbuddy-web -n 50 --no-pager
```

If you get a login prompt but credentials don’t work, check the auth file on the Pi boot partition:
- `/boot/firmware/ovbuddy-web-auth.txt` or `/boot/ovbuddy-web-auth.txt`

## AP fallback

If the device enters AP mode (default config), connect to the WiFi network:
- SSID: `OVBuddy` (default)
- Password: `password` (default)

Then open `http://192.168.4.1:8080`.

### Cannot scan for WiFi networks in AP mode

**Problem**: When accessing the web interface through the access point (AP mode), clicking "Scan for Networks" returns an error: "Operation not permitted" or "Cannot scan for WiFi networks while in Access Point mode."

**Explanation**: This is a hardware limitation. When the Raspberry Pi's WiFi interface (`wlan0`) is operating as an access point (hosting the WiFi network you're connected to), it cannot simultaneously scan for other WiFi networks. A single WiFi interface can only operate in one mode at a time:
- **Station mode** (client): Can connect to WiFi networks and scan for available networks
- **Access Point mode** (AP): Hosts a WiFi network for others to connect to, but cannot scan

**Solutions**:

1. **Use the Manual WiFi Connection form** (Recommended):
   - The web interface includes a "Manual WiFi Connection" form specifically for this situation
   - Located in the WiFi Configuration section, above the network scan results
   - Simply enter your WiFi network name (SSID) and password
   - Click "Connect to Network"
   - The device will attempt to connect and automatically restart the display service
   - Once connected, the device will exit AP mode and scanning will become available

2. **Use a second WiFi adapter** (Advanced):
   - Connect a USB WiFi dongle to the Raspberry Pi
   - The built-in WiFi (`wlan0`) can host the AP while the USB adapter (`wlan1`) scans for networks
   - This requires additional configuration to specify which interface to use for scanning

3. **Force exit AP mode temporarily**:
   - If you have a known WiFi network configured (from a previous connection), the device will automatically try to reconnect
   - The `ovbuddy-wifi` service monitors for available configured networks and will automatically switch back to client mode when your WiFi network is in range

**Workaround**: If you need to see available networks while in AP mode, you can use a phone or laptop to scan for WiFi networks in the area, then manually enter the SSID and password in the OVBuddy web interface.

## Services don’t start after reboot

Use the repair helper:

```bash
cd scripts
./fix-boot-services.sh
```

Or on the Pi:

```bash
sudo systemctl status ovbuddy ovbuddy-web ovbuddy-wifi avahi-daemon
sudo journalctl -u ovbuddy -u ovbuddy-web -n 100 --no-pager
```







