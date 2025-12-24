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

## Hardware Requirements

- **Raspberry Pi Zero W 1.1** (or any Raspberry Pi with GPIO)
- **Waveshare 2.13" e-Paper Display V4** (250x122 pixels)
- MicroSD card (8GB or larger)
- Power supply (5V micro USB)

## Quick Start

### 1. Prepare the SD Card

Use the provided setup script to prepare an SD card with Raspberry Pi OS Lite:

```bash
cd scripts
./setup-sd-card.sh
```

This will guide you through:
- Installing Raspberry Pi OS Lite (32-bit, Legacy)
- Configuring WiFi and SSH
- Setting hostname and credentials

**Manual Setup:**
1. Download [Raspberry Pi Imager](https://www.raspberrypi.com/software/)
2. Choose **Raspberry Pi Zero W** as device
3. Choose **Raspberry Pi OS Lite (32-bit, Legacy)** as OS
4. Configure settings (hostname: `ovbuddy`, enable SSH, WiFi credentials)
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

### 4. Setup Passwordless Sudo (Optional but Recommended)

```bash
cd scripts
./setup-passwordless-sudo.sh
```

This allows the web interface to manage WiFi and services without password prompts.

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

See [WEB_INTERFACE.md](dist/WEB_INTERFACE.md) for detailed documentation, [WIFI_SETUP.md](WIFI_SETUP.md) for WiFi troubleshooting, and [demo.html](demo.html) for a visual preview.

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
│   └── WEB_INTERFACE.md      # Web interface documentation
├── scripts/                   # Deployment and utility scripts
│   ├── deploy.sh             # Main deployment script
│   ├── setup-sd-card.sh      # SD card setup helper
│   ├── setup-passwordless-sudo.sh  # Sudo configuration
│   ├── restart-service.sh    # Restart services
│   ├── stop-service.sh       # Stop services
│   └── display-image.sh      # Display custom images
├── assets/                    # Images and resources
├── demo.html                  # Web interface theme demo
├── CHANGES.md                 # Recent changes documentation
├── THEME_PREVIEW.md           # Theme customization guide
└── WIFI_SETUP.md              # WiFi network switching guide
```

## Troubleshooting

### Service won't start

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

**Alternative (fix only, no full deployment):**
```bash
cd scripts
./fix-avahi-boot.sh
```

This script will:
- Ensure avahi-daemon is installed and enabled
- Unmask avahi-daemon (in case it was masked)
- Update the fix-bonjour service with better boot handling
- Start avahi-daemon if it's not running

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

### Web interface shutdown/restart commands timeout

If the "Shutdown & Clear Display" button or service control commands timeout after fixing the avahi-daemon boot issue, this is caused by systemctl blocking.

**Quick Fix (just redeploy):**
```bash
cd scripts
./deploy.sh
```

This will automatically update the fix-bonjour script with the `--no-block` fix.

**Alternative (fix only, no full deployment):**
```bash
cd scripts
./fix-shutdown-timeout.sh
```

**What causes this:**
- The fix-bonjour service manages avahi-daemon during boot
- Without `--no-block`, systemctl commands wait for services to fully start
- This creates deadlocks when multiple systemctl commands run simultaneously
- Web interface commands timeout (10 second limit)

**After applying the fix:**
- systemctl commands return immediately
- No more timeouts or deadlocks
- Web interface works reliably

### WiFi not working

**See [WIFI_SETUP.md](WIFI_SETUP.md) for comprehensive WiFi troubleshooting.**

Quick checks:
1. Check WiFi status via web interface
2. Verify passwordless sudo is configured: `./scripts/setup-passwordless-sudo.sh`
3. Check if wpa_supplicant.conf exists: `ls -la /etc/wpa_supplicant/`
4. Restart WiFi:
   ```bash
   sudo systemctl restart wpa_supplicant
   ```

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

```bash
cd scripts
./display-image.sh path/to/image.jpg
```

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

