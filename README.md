# OVBuddy

OVBuddy is a Swiss public transport departure display for Raspberry Pi with e-ink display. It shows real-time departure information from Swiss public transport stations (trains, trams, buses) on a Waveshare 2.13" e-ink display.

![OVBuddy Display](assets/test-output.jpg)

## Features

- 🚆 Real-time departure information from Swiss public transport API
- 🖥️ E-ink display (Waveshare 2.13" V4) for low power consumption
- 🌐 **Hacker-style terminal web interface** for configuration
- 📱 QR code for easy access to web interface
- 🔄 Automatic updates at configurable intervals
- ⚙️ Configurable stations, lines, and display settings
- 📡 Bonjour/mDNS support for easy network access
- 🔌 Runs as systemd service on boot
- 💻 Service management via web interface
- 📶 **WiFi network switching** via web interface (no SSH needed!)
- 🔄 **Automatic WiFi Access Point fallback** when network is unavailable

## Hardware Requirements

- **Raspberry Pi Zero W 1.1** (or any Raspberry Pi with GPIO)
- **Waveshare 2.13" e-Paper Display V4** (250x122 pixels)
- MicroSD card (8GB or larger)
- Power supply (5V micro USB)

## Quick Start

### 1. Prepare the SD Card

Use **Raspberry Pi Imager** (GUI). Full step-by-step instructions:
- `doc/SD_CARD_SETUP.md`

**Quick version:**
1. Download [Raspberry Pi Imager](https://www.raspberrypi.com/software/)
2. Choose **Raspberry Pi Zero W** as device
3. Choose **Raspberry Pi OS (Legacy, 32-bit) Lite** as OS
4. Configure settings (hostname: `ovbuddy`, enable SSH, WiFi credentials, WiFi country)
5. Write to SD card

### 2. Configure Connection

Create a `.env` file in the project root:

```bash
PI_HOST=ovbuddy.local
PI_USER=pi
PI_PASSWORD=your_password
```

### 3. Deploy to Raspberry Pi

```bash
cd scripts
./deploy.sh
```

This will:
- Copy all files to the Raspberry Pi
- Install Python dependencies
- Configure Bonjour/mDNS
- Install and start the systemd services

**Optional flags:**
- `-main`: Deploy only `ovbuddy.py` (for quick iterations)
- `-reboot`: Reboot after deployment and verify services are running

### 4. Setup Passwordless Sudo (Required)

`./scripts/deploy.sh` will attempt to configure passwordless sudo automatically during deployment.

If deployment couldn’t apply it (or you want to apply it explicitly), run:

```bash
cd scripts
./setup-passwordless-sudo.sh
```

This is required for the web interface to manage WiFi and services without password prompts.

## Configuration

### Web Interface

Access the **hacker-style terminal web interface** at:
- `http://ovbuddy.local:8080` (via Bonjour)
- `http://[raspberry-pi-ip]:8080` (via IP address)

Or scan the QR code displayed on the e-ink screen during startup.

**New Features:**
- 🎨 Terminal/hacker theme with CRT effects
- 📝 Template-based architecture for easy customization
- 🔧 Service management (start/stop/restart)
- 📶 WiFi network scanning and connection
- 📊 Real-time status updates

The web interface runs on the Pi at port `8080` (deployed via `./scripts/deploy.sh`).

### Configuration Options

- **Stations**: One or more station names to monitor
- **Lines**: Filter by specific line numbers (e.g., S4, T13, T5)
- **Refresh Interval**: How often to update the display (in seconds)
- **Display Settings**: Invert colors, flip display, partial refresh
- **Max Departures**: Number of connections to show
- **WiFi Management**: Scan and connect to WiFi networks

### Manual Configuration

Edit `/home/pi/ovbuddy/config.json` on the Raspberry Pi:

```json
{
  "stations": ["Zürich Saalsporthalle", "Zürich, Saalsporthalle"],
  "lines": ["S4", "T13", "T5"],
  "refresh_interval": 20,
  "inverted": false,
  "flip_display": false,
  "max_departures": 6
}
```

## Project Structure

```
OVBuddy/
├── dist/                      # Deployment files
│   ├── ovbuddy.py            # Main display application
│   ├── ovbuddy_web.py        # Web server application
│   ├── ovbuddy.service       # Display systemd service
│   ├── ovbuddy-web.service   # Web server systemd service
│   ├── ovbuddy-wifi.service  # WiFi monitor systemd service
│   ├── templates/            # HTML templates
│   │   └── index.html        # Main web interface template
│   ├── static/               # Static web assets
│   │   ├── css/
│   │   │   └── terminal.css  # Terminal theme styles
│   │   └── js/
│   │       └── app.js        # Web interface JavaScript
│   ├── gpio-cleanup.py       # GPIO cleanup script
│   ├── config.json           # Configuration file
│   ├── epd2in13_V4.py        # E-ink display driver
│   ├── epdconfig.py          # Display configuration
│   ├── test_templates.py     # Template testing script
├── scripts/                   # Deployment and utility scripts
│   ├── deploy.sh             # Main deployment script
│   ├── setup-passwordless-sudo.sh  # Sudo configuration
│   ├── restart-service.sh    # Restart services
│   ├── stop-service.sh       # Stop services
│   ├── trigger-refresh.sh    # Ask the running service to refresh soon
│   └── find-pi.sh            # Locate the Pi on your LAN
├── assets/                    # Images and resources
└── doc/                       # Documentation (setup, troubleshooting, etc.)
```

## Troubleshooting

### Find the Pi / network issues

- Try: `ping ovbuddy.local`
- Or run:

```bash
./scripts/find-pi.sh
```

If you suspect an SD-card / first-boot problem, see:
- `doc/SD_CARD_TROUBLESHOOTING.md`

### Service won’t start (on the Pi)

Check service status:
```bash
ssh pi@ovbuddy.local
sudo systemctl status ovbuddy
sudo journalctl -u ovbuddy -n 50
```

Common issues:
- **GPIO busy**: The GPIO cleanup script should handle this automatically
- **Missing dependencies**: Run `./deploy.sh` again
- **Display not connected**: Check physical connections

### Can't access web interface

1. Check if web service is running:
   ```bash
   sudo systemctl status ovbuddy-web
   ```

2. Find IP address:
   ```bash
   hostname -I
   ```

3. Flush DNS cache on Mac:
   ```bash
   sudo dscacheutil -flushcache
   sudo killall -HUP mDNSResponder
   ```

### Bonjour/mDNS not working after reboot

If `ovbuddy.local` doesn't resolve after a reboot, the avahi-daemon service may not be starting on boot.

**Quick Fix (just redeploy):**
```bash
cd scripts
./deploy.sh
```

This will automatically apply all fixes.

**Manual Fix on Pi:**
```bash
ssh pi@[pi-ip-address]
sudo systemctl unmask avahi-daemon
sudo systemctl enable avahi-daemon
sudo systemctl start avahi-daemon
```

**Verify the fix:**
```bash
# Check avahi-daemon status
ssh pi@ovbuddy.local 'sudo systemctl status avahi-daemon'

# Check fix-bonjour service
ssh pi@ovbuddy.local 'sudo systemctl status fix-bonjour'

# View logs
ssh pi@ovbuddy.local 'sudo journalctl -u avahi-daemon -u fix-bonjour -n 50'
```

**Test after reboot:**
```bash
# Reboot the Pi
ssh pi@ovbuddy.local 'sudo reboot'

# Wait 60 seconds, then test
ping ovbuddy.local
ssh pi@ovbuddy.local
```

### WiFi not working

Quick checks:
1. Check WiFi status via web interface
2. Verify passwordless sudo is configured: `./scripts/setup-passwordless-sudo.sh`
3. Check if wpa_supplicant.conf exists: `ls -la /etc/wpa_supplicant/`
4. Restart WiFi:
   ```bash
   sudo systemctl restart wpa_supplicant
   ```

### Can't connect to configured WiFi

**WiFi Access Point Fallback** is automatically enabled when you deploy OVBuddy. When the configured WiFi network is unavailable, the device will automatically create its own access point.

**How it works:**
1. Device tries to connect to configured WiFi
2. After 2 minutes of no connection, switches to AP mode
3. Creates WiFi network "OVBuddy" (configurable)
4. Connect to it and access web interface at `http://192.168.4.1:8080`
5. Configure WiFi through the web interface
6. Automatically reconnects when WiFi is available

**To enable/disable:**
- Via web interface: Toggle "Enable WiFi Access Point Fallback"
- Via config.json: Set `"ap_fallback_enabled": true` or `false`
- Then redeploy: `./scripts/deploy.sh`

## Service Management

```bash
# Display service
sudo systemctl status ovbuddy          # Check status
sudo systemctl restart ovbuddy         # Restart
sudo systemctl stop ovbuddy            # Stop
sudo systemctl start ovbuddy           # Start
sudo journalctl -u ovbuddy -f          # View logs

# Web service
sudo systemctl status ovbuddy-web      # Check status
sudo systemctl restart ovbuddy-web     # Restart
sudo journalctl -u ovbuddy-web -f      # View logs

# WiFi monitor service (if installed)
sudo systemctl status ovbuddy-wifi     # Check status
sudo systemctl restart ovbuddy-wifi    # Restart
sudo journalctl -u ovbuddy-wifi -f     # View logs
```

## Development

### Local Testing

Run without display hardware:
```bash
TEST_MODE=1 python3 dist/ovbuddy.py --test
```

### Deploy Main File Only

For quick iterations:
```bash
cd scripts
./deploy.sh -main
```

### Deploy and Reboot

To deploy and reboot the device, then check service status:
```bash
cd scripts
./deploy.sh -reboot
```

This will:
- Deploy all files
- Reboot the Raspberry Pi
- Wait for it to come back online
- Check status of both `ovbuddy` and `ovbuddy-web` services
- Show recent logs if any service fails to start

You can combine flags:
```bash
./deploy.sh -main -reboot  # Deploy only main file and reboot
```

### Display Custom Images

Use `dist/display_image.py` on the Pi (it is deployed into `/home/pi/ovbuddy/`).

## Technical Details

### Dependencies

- Python 3.11+
- Flask (web server)
- pyqrcode, pypng (QR code generation)
- gpiozero, lgpio (GPIO control)
- spidev (SPI communication)
- PIL/Pillow (image processing)
- requests (API calls)

### API

Uses the [Swiss public transport API](https://transport.opendata.ch/):
- Endpoint: `https://transport.opendata.ch/v1/stationboard`
- No API key required
- Real-time departure data

### Display

- **Model**: Waveshare 2.13" e-Paper Display V4
- **Resolution**: 250x122 pixels
- **Connection**: SPI interface
- **Refresh**: Full refresh on startup, partial refresh for updates
- **Power**: Ultra-low power consumption when idle

### GPIO Pins

| Pin | Function |
|-----|----------|
| 17  | RST      |
| 25  | DC       |
| 8   | CS       |
| 24  | BUSY     |
| 18  | PWR      |
| 10  | MOSI     |
| 11  | SCLK     |

## License

This project uses the Waveshare e-Paper library which is provided under the MIT License.

## Credits

- E-Paper display driver: [Waveshare](https://www.waveshare.com/)
- Transport data: [Swiss public transport API](https://transport.opendata.ch/)
- Developed for personal use with Raspberry Pi Zero W 1.1

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review service logs: `sudo journalctl -u ovbuddy -n 100`
3. Check GPIO status: `gpioinfo | grep -E "17|18|24|25"`

## Updates

To update OVBuddy:
```bash
cd scripts
./deploy.sh
```

This will deploy the latest version and restart services.

