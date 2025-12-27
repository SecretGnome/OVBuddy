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




