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

Use the provided setup script to prepare an SD card with Raspberry Pi OS Lite:

```bash
cd scripts
./setup-sd-card.sh
```

This will guide you through:
- Installing Raspberry Pi OS Lite (32-bit, Legacy)
- Configuring WiFi and SSH
- Setting hostname and credentials

**Automated Setup (Optional):**

To skip manual prompts, create a `setup.env` file in the project root:

```bash
cp setup.env.example setup.env
# Edit setup.env with your WiFi credentials and preferences
```

Then run the setup script - it will automatically use your configuration

**Manual Setup:**
1. Download [Raspberry Pi Imager](https://www.raspberrypi.com/software/)
2. Choose **Raspberry Pi Zero W** as device
3. Choose **Raspberry Pi OS Lite (32-bit, Legacy)** as OS
4. Configure settings (hostname: `ovbuddy`, enable SSH, WiFi credentials)
5. Write to SD card

### 2. Configure Connection

Create a `setup.env` file in the project root:

```bash
cp setup.env.example setup.env
# Edit setup.env with your credentials
PI_HOST=ovbuddy.local
PI_USER=pi
PI_PASSWORD=your_password
```

**Note:** The SD card setup now installs Avahi automatically, so `ovbuddy.local` should work after first boot (wait 4-5 minutes for first boot + Avahi installation).

If `.local` doesn't work, see the troubleshooting section below to find the IP address.

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

See [WEB_INTERFACE.md](dist/WEB_INTERFACE.md) for detailed documentation, [WIFI_SETUP.md](WIFI_SETUP.md) for WiFi troubleshooting, [WIFI_AP_FALLBACK.md](WIFI_AP_FALLBACK.md) for access point fallback setup, and [demo.html](demo.html) for a visual preview.

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

### Pi Not Reachable After SD Card Setup

If you've just set up the SD card and the Pi is not reachable at `ovbuddy.local`:

**This is expected!** The fresh Raspberry Pi OS Lite image doesn't include Avahi (mDNS service) by default.

**Quick Solution:**

1. **Find the Pi's IP address:**
   ```bash
   cd scripts
   ./find-pi.sh
   ```
   
   Or check your router's admin page for a device named "ovbuddy".

2. **Update `setup.env` temporarily with the IP:**
   ```bash
   PI_HOST=192.168.1.xxx  # Use the actual IP
   ```

3. **Run the deploy script** (this will install Avahi automatically):
   ```bash
   cd scripts
   ./deploy.sh
   ```

4. **After deployment, change back to `.local`:**
   ```bash
   PI_HOST=ovbuddy.local
   ```

5. **Test the connection:**
   ```bash
   ping ovbuddy.local
   ssh pi@ovbuddy.local
   ```

**Alternative Methods to Find IP:**
- Check router admin page for "ovbuddy"
- Use `arp-scan`: `brew install arp-scan && sudo arp-scan --localnet | grep -i raspberry`
- Use `nmap`: `brew install nmap && nmap -sn 192.168.1.0/24 | grep -B 2 Raspberry`

**Common Issues:**
- **Pi hasn't finished booting**: Wait 3-4 minutes from first power-on (includes auto-reboot)
- **WiFi connection failed**: Check SSID/password in `setup.env`
- **5GHz WiFi**: Pi Zero W only supports 2.4GHz networks
- **Wrong country code**: Must match your location (e.g., `CH`, `US`, `GB`)

See [SD_CARD_TROUBLESHOOTING.md](doc/SD_CARD_TROUBLESHOOTING.md) and [AVAHI_MISSING_FIX.md](doc/AVAHI_MISSING_FIX.md) for detailed information.

### Can't SSH into Raspberry Pi

If you can reach the Pi via `ovbuddy.local` (ping works) but SSH authentication fails with "Permission denied":

**Quick Test:**
```bash
cd scripts
./test-ssh.sh
```

This diagnostic script will test:
- Network connectivity
- mDNS resolution
- SSH port accessibility
- SSH authentication (both key and password)

**Common Causes:**
1. **Password hash issue**: The password may not have been set correctly during SD card setup
2. **Wrong password**: Double-check your password in `setup.env`
3. **First boot not complete**: Wait 3-5 minutes after first power-on (includes auto-reboot)

**Solutions:**

**Option A: Recreate SD Card (Recommended)**
```bash
cd scripts
./setup-sd-card.sh
```

The updated script now uses OpenSSL for more reliable password hash generation.

**Option B: Manual Password Reset**

If you have a monitor and keyboard:
1. Connect them to the Pi
2. Log in at the console
3. Run: `passwd`
4. Set a new password

**Option C: Use SSH Keys**

Set up key-based authentication instead:
```bash
ssh-keygen -t ed25519
ssh-copy-id pi@ovbuddy.local
```

See [SSH_PASSWORD_FIX.md](doc/SSH_PASSWORD_FIX.md) for detailed troubleshooting.

### Force AP Mode Not Working

If the "Force AP Mode" button doesn't work or the device reconnects to known WiFi instead of entering AP mode, run the diagnostic script:

```bash
cd scripts
./diagnose-force-ap.sh
```

This will check:
- WiFi manager type (NetworkManager vs wpa_supplicant)
- Current WiFi connection status
- Auto-connect settings for configured networks
- Force AP flag status
- wifi-monitor service status
- Whether device is in AP mode

**Common Issue: Device Reconnects to WiFi After Reboot**

This happens when auto-reconnect is not properly disabled. The fix:
1. Redeploy with the updated scripts: `./scripts/deploy.sh`
2. The updated `force-ap-mode.sh` now disables auto-connect before rebooting
3. This prevents the device from reconnecting to known networks
4. wifi-monitor can then properly enter AP mode

See [FORCE_AP_FIX_AUTOCONNECT.md](doc/FORCE_AP_FIX_AUTOCONNECT.md) for technical details and [FORCE_AP_TROUBLESHOOTING.md](doc/FORCE_AP_TROUBLESHOOTING.md) for detailed troubleshooting.

### Services don't start on boot

If services don't start automatically after reboot, use the diagnostic script:

```bash
cd scripts
./fix-boot-services.sh
```

This will check and fix:
- avahi-daemon (Bonjour/mDNS)
- ovbuddy-wifi (WiFi monitor)
- ovbuddy and ovbuddy-web services

See [BOOT_SERVICES.md](BOOT_SERVICES.md) for detailed troubleshooting.

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

### Can't connect to configured WiFi

**WiFi Access Point Fallback** is automatically enabled when you deploy OVBuddy. When the configured WiFi network is unavailable, the device will automatically create its own access point.

See [WIFI_AP_FALLBACK.md](WIFI_AP_FALLBACK.md) for detailed information.

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

