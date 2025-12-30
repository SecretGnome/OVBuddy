# Web interface

The OVBuddy web UI runs on port **8080** (service: `ovbuddy-web`).

## URLs

- Normal network: `http://<pi-host-or-ip>:8080`
- AP fallback (when enabled): `http://192.168.4.1:8080`

## Login (Basic Auth)

By default, the web UI uses HTTP Basic Auth. Credentials are stored on the Pi’s boot partition as a plain text file:

- Newer images: `/boot/firmware/ovbuddy-web-auth.txt`
- Older images: `/boot/ovbuddy-web-auth.txt`

Supported formats:

```text
USERNAME=admin
PASSWORD=password
```

or:

```text
admin:password
```

If the file is missing/invalid, OVBuddy initializes it with **`admin` / `password`**.

Updating credentials from the web UI requires passwordless sudo (the deploy script sets this up).

## Web UI modules (panels + backend endpoints)

The UI exposes toggles for “modules”. When a module is disabled, the panel is hidden and its backend endpoints are disabled.

The module flags are stored next to `ovbuddy.py` as:
- `/home/<user>/ovbuddy/web_settings.json`

Default modules:
- `web_auth_basic`: when disabled, Basic Auth is not required
- `config_json`: enables the config editor (and using `config.json`)
- `systemctl_status`: enables service status/actions
- `iwconfig`: enables WiFi scanning/switching endpoints
- `shutdown`: enables shutdown/reboot endpoints

## WiFi Configuration

The web interface allows you to:
- View current WiFi status
- Scan for available networks
- Connect to WiFi networks
- Force the device into AP mode

**Important limitation**: When the device is in Access Point (AP) mode, WiFi scanning is not available. This is because the WiFi interface is being used to host the access point and cannot simultaneously scan for other networks. 

To configure WiFi while in AP mode:
1. Manually enter the SSID and password of your network (without scanning)
2. Click "Connect"
3. Once connected, the device will exit AP mode and scanning will become available

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md#cannot-scan-for-wifi-networks-in-ap-mode) for more details.

