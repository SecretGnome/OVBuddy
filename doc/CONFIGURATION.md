# Configuration

OVBuddy reads configuration from `config.json` in the same directory as `ovbuddy.py`:

- `/home/<user>/ovbuddy/config.json`

The repository ships defaults in `dist/config.json`.

## Common settings (and defaults)

- `stations` (array of strings): `["Zürich Saalsporthalle", "Zürich, Saalsporthalle"]`
- `lines` (array of strings): `["S4", "T13", "T5"]`
- `refresh_interval` (seconds): `20`
- `qr_code_display_duration` (seconds): `10`
- `max_departures` (int): `6`
- `inverted` (bool): `false`

### Display orientation

- `display_orientation` (string): one of `bottom` (default), `top`, `left`, `right`
- `flip_display` (bool): legacy compatibility; if `display_orientation` is set, it takes precedence
- `use_partial_refresh` (bool): `false`

### Auto-update

- `auto_update` (bool): `true`
- `update_repository_url` (string): `https://github.com/SecretGnome/OVBuddy`

### WiFi AP fallback

- `ap_fallback_enabled` (bool): `true`
- `ap_ssid` (string): `OVBuddy`
- `ap_password` (string): `password`
- `display_ap_password` (bool): `true`

The AP web UI is reachable at `http://192.168.4.1:8080`.

### Stored WiFi networks

These are maintained by the device/web UI:
- `last_wifi_ssid` (string)
- `last_wifi_password` (string)
- `known_wifis` (object)

## Example

```json
{
  "stations": ["Zürich HB"],
  "lines": ["S4", "T13"],
  "refresh_interval": 30,
  "display_orientation": "bottom",
  "use_partial_refresh": false,
  "max_departures": 6,
  "ap_fallback_enabled": true,
  "ap_ssid": "OVBuddy",
  "ap_password": "password"
}
```

## Note about `dist/config.json`

`dist/config.json` currently includes `config_display_duration`, but the current `dist/ovbuddy.py` does not read that key (it is ignored).






