#!/usr/bin/env python3

"""
WiFi Monitor and Access Point Fallback for OVBuddy

This script monitors the WiFi connection and automatically creates an access point
when the configured WiFi network is unavailable. This allows users to connect
directly to the Raspberry Pi to configure WiFi settings.

The script:
1. Checks if WiFi is connected every 30 seconds
2. If disconnected for more than 2 minutes, switches to AP mode
3. When in AP mode, periodically checks if the configured WiFi is available
4. Automatically switches back to client mode when WiFi becomes available
"""

import subprocess
import time
import json
import os
import sys
import signal
import logging
from pathlib import Path

# Configuration
CONFIG_FILE = "/home/pi/ovbuddy/config.json"
FORCE_AP_FLAG = "/var/lib/ovbuddy-force-ap"  # Flag file to force AP mode on boot
CHECK_INTERVAL = 30  # seconds between checks
DISCONNECT_THRESHOLD = 120  # seconds before switching to AP mode
AP_CHECK_INTERVAL = 60  # seconds between WiFi scans when in AP mode
BOOT_CONNECT_TIMEOUT = 60  # seconds to attempt last-known WiFi on boot before AP fallback

# Logging setup
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler('/var/log/ovbuddy-wifi.log')
    ]
)
logger = logging.getLogger(__name__)

# Global state
current_mode = None  # 'client' or 'ap'
disconnect_start_time = None
running = True
wifi_manager = None  # 'networkmanager' or 'wpa_supplicant'
ovbuddy_was_active_before_ap = False  # track to avoid display conflicts in AP mode
boot_connect_deadline = None  # if set, suppress AP fallback until this time
boot_last_wifi = None  # {"ssid": "...", "password": "..."} for boot attempts

def ensure_networkmanager_wifi_ready():
    """Best-effort: ensure NM can manage wlan0 and autoconnect is enabled.

    force-ap-mode.sh intentionally disables autoconnect and may set wlan0 unmanaged.
    If the user has since configured WiFi again, we want normal behavior restored
    so the device can reconnect on reboot.
    """
    try:
        # Make sure NM is managing wlan0
        subprocess.run(['sudo', 'nmcli', 'device', 'set', 'wlan0', 'managed', 'yes'], timeout=10, capture_output=True)
        # Ensure WiFi radio is on
        subprocess.run(['sudo', 'nmcli', 'radio', 'wifi', 'on'], timeout=10, capture_output=True)

        # Re-enable autoconnect for all WiFi connections
        result = subprocess.run(
            ['sudo', 'nmcli', '-t', '-f', 'NAME,TYPE', 'connection', 'show'],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            for line in result.stdout.strip().split('\n'):
                if ':802-11-wireless' in line:
                    conn_name = line.split(':')[0]
                    subprocess.run(
                        ['sudo', 'nmcli', 'connection', 'modify', conn_name, 'connection.autoconnect', 'yes'],
                        timeout=5,
                        capture_output=True
                    )
        # Trigger NM to try connecting
        subprocess.run(['sudo', 'nmcli', 'device', 'connect', 'wlan0'], timeout=10, capture_output=True)
    except Exception as e:
        logger.debug(f"ensure_networkmanager_wifi_ready failed: {e}")

def clear_force_ap_flag():
    """Remove the FORCE_AP_FLAG if present.

    This flag is intended as a one-shot request (e.g. set by force-ap-mode.sh).
    Once we're connected to normal WiFi again, it should be cleared so it
    doesn't keep influencing mode decisions after reboot.
    """
    try:
        if os.path.exists(FORCE_AP_FLAG):
            os.remove(FORCE_AP_FLAG)
            logger.info("Cleared force AP mode flag file")
    except Exception as e:
        logger.warning(f"Could not clear force AP flag: {e}")


def signal_handler(signum, frame):
    """Handle shutdown signals gracefully"""
    global running
    logger.info(f"Received signal {signum}, shutting down...")
    running = False
    # Try to restore client mode before exiting
    if current_mode == 'ap':
        logger.info("Restoring client mode before exit...")
        switch_to_client_mode()
    sys.exit(0)


def detect_wifi_manager():
    """Detect which WiFi manager is in use: NetworkManager or wpa_supplicant"""
    try:
        # Check if NetworkManager is running and managing wlan0
        result = subprocess.run(
            ['nmcli', 'device', 'status'],
            capture_output=True,
            text=True,
            timeout=5
        )
        
        if result.returncode == 0 and 'wlan0' in result.stdout:
            # Check if wlan0 is managed by NetworkManager
            for line in result.stdout.split('\n'):
                if 'wlan0' in line and 'unmanaged' not in line.lower():
                    logger.info("Detected NetworkManager managing wlan0")
                    return 'networkmanager'
        
        # Check if wpa_supplicant is running
        result = subprocess.run(
            ['systemctl', 'is-active', 'wpa_supplicant'],
            capture_output=True,
            text=True,
            timeout=5
        )
        
        if result.returncode == 0 and result.stdout.strip() == 'active':
            logger.info("Detected wpa_supplicant managing WiFi")
            return 'wpa_supplicant'
        
        # Default to wpa_supplicant
        logger.warning("Could not detect WiFi manager, defaulting to wpa_supplicant")
        return 'wpa_supplicant'
        
    except Exception as e:
        logger.error(f"Error detecting WiFi manager: {e}")
        return 'wpa_supplicant'


def load_config():
    """Load configuration from config.json"""
    try:
        if os.path.exists(CONFIG_FILE):
            with open(CONFIG_FILE, 'r') as f:
                config = json.load(f)
                return config
        else:
            logger.warning(f"Config file not found: {CONFIG_FILE}")
            return {}
    except Exception as e:
        logger.error(f"Error loading config: {e}")
        return {}


def save_config(config):
    """Save configuration back to config.json (best-effort)."""
    try:
        os.makedirs(os.path.dirname(CONFIG_FILE), exist_ok=True)
        with open(CONFIG_FILE, 'w') as f:
            json.dump(config, f, indent=2)
        return True
    except Exception as e:
        logger.warning(f"Error saving config: {e}")
        return False


def get_ap_config():
    """Get access point configuration from config.json"""
    config = load_config()
    
    # Default AP settings
    ap_ssid = config.get('ap_ssid', 'OVBuddy')
    ap_password = config.get('ap_password', '')  # Empty = open network
    ap_enabled = config.get('ap_fallback_enabled', True)
    
    return {
        'ssid': ap_ssid,
        'password': ap_password,
        'enabled': ap_enabled
    }


def get_last_wifi_config():
    """Get last-known WiFi credentials from config.json (saved by ovbuddy web UI)."""
    config = load_config()
    return {
        "ssid": str(config.get("last_wifi_ssid", "") or ""),
        "password": str(config.get("last_wifi_password", "") or "")
    }


def _extract_wpa_supplicant_psk(ssid):
    """Best-effort: extract PSK for SSID from wpa_supplicant config (returns '' for open or not found)."""
    candidates = [
        "/etc/wpa_supplicant/wpa_supplicant.conf",
        "/etc/wpa_supplicant/wpa_supplicant-wlan0.conf",
    ]
    for path in candidates:
        try:
            if not os.path.exists(path):
                continue
            text = Path(path).read_text(errors="ignore")
            in_net = False
            cur_ssid = None
            cur_psk = None
            for raw in text.splitlines():
                line = raw.strip()
                if not line or line.startswith("#"):
                    continue
                if line.startswith("network={"):
                    in_net = True
                    cur_ssid = None
                    cur_psk = None
                    continue
                if in_net and line.startswith("}"):
                    if cur_ssid == ssid and cur_psk is not None:
                        return cur_psk
                    in_net = False
                    cur_ssid = None
                    cur_psk = None
                    continue
                if not in_net:
                    continue
                if line.startswith("ssid="):
                    val = line.split("=", 1)[1].strip()
                    if val.startswith('"') and val.endswith('"'):
                        val = val[1:-1]
                    cur_ssid = val
                elif line.startswith("psk="):
                    val = line.split("=", 1)[1].strip()
                    if val.startswith('"') and val.endswith('"'):
                        val = val[1:-1]
                    cur_psk = val
                elif line.startswith("key_mgmt=") and "NONE" in line:
                    # Open network
                    if cur_psk is None:
                        cur_psk = ""
            # no match in this file
        except Exception:
            continue
    return ""


def _extract_nm_psk_for_active_wifi(ssid):
    """Best-effort: read PSK from NetworkManager for the active WiFi connection."""
    try:
        # Find active WiFi connection name
        active = subprocess.run(
            ["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show", "--active"],
            capture_output=True,
            text=True,
            timeout=5
        )
        if active.returncode != 0:
            return ""
        conn_name = None
        for line in active.stdout.strip().splitlines():
            if not line:
                continue
            name, typ = (line.split(":", 1) + [""])[:2]
            if typ == "802-11-wireless":
                conn_name = name
                break
        if not conn_name:
            return ""

        # Ensure it matches the SSID we're connected to (best-effort)
        nm_ssid = subprocess.run(
            ["nmcli", "-t", "-f", "ACTIVE,SSID", "dev", "wifi"],
            capture_output=True,
            text=True,
            timeout=5
        )
        if nm_ssid.returncode == 0:
            # Look for a line like: "yes:<ssid>"
            for line in nm_ssid.stdout.strip().splitlines():
                if line.startswith("yes:"):
                    active_ssid = line.split(":", 1)[1]
                    if active_ssid and active_ssid != ssid:
                        return ""
                    break

        # Pull PSK (may be empty if not stored)
        psk = subprocess.run(
            ["nmcli", "-s", "-g", "802-11-wireless-security.psk", "connection", "show", conn_name],
            capture_output=True,
            text=True,
            timeout=5
        )
        if psk.returncode == 0:
            return (psk.stdout or "").strip()
    except Exception:
        pass
    return ""


def persist_last_wifi_credentials(ssid):
    """Persist last connected SSID + password (best-effort) into config.json."""
    if not ssid:
        return
    try:
        config = load_config()
        changed = False

        if str(config.get("last_wifi_ssid", "") or "") != ssid:
            config["last_wifi_ssid"] = ssid
            changed = True

        # Only fill password if we can determine it (and don't overwrite non-empty value with empty).
        existing_pwd = str(config.get("last_wifi_password", "") or "")
        pwd = ""
        if wifi_manager == "networkmanager":
            pwd = _extract_nm_psk_for_active_wifi(ssid)
        if not pwd:
            pwd = _extract_wpa_supplicant_psk(ssid)

        if pwd and pwd != existing_pwd:
            config["last_wifi_password"] = pwd
            changed = True

        if changed:
            save_config(config)
            logger.info(f"Saved last WiFi: ssid='{ssid}'" + (" (password saved)" if pwd else ""))
    except Exception as e:
        logger.warning(f"Could not persist last WiFi credentials: {e}")


def attempt_connect_to_last_wifi(ssid, password, timeout_seconds=BOOT_CONNECT_TIMEOUT):
    """Try to connect to the provided WiFi for up to timeout_seconds.

    Returns True if connected, False otherwise.
    """
    global wifi_manager
    if not ssid:
        return False

    logger.info(f"Attempting to connect to last-known WiFi '{ssid}' for up to {timeout_seconds}s...")
    start = time.time()

    def _try_nmcli():
        try:
            # Prefer connecting without providing a password, so NetworkManager can
            # use its stored connection profile/secret if available.
            cmd = ['nmcli', 'device', 'wifi', 'connect', ssid]
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
            if result.returncode == 0:
                return True

            # If that fails and we have a password, try again with it (passphrase).
            # (If the saved value is a 64-hex PSK, nmcli won't accept it as a passphrase.)
            if password:
                is_hex_psk = (len(password) == 64 and all(c in "0123456789abcdefABCDEF" for c in password))
                if not is_hex_psk:
                    cmd2 = ['nmcli', 'device', 'wifi', 'connect', ssid, 'password', password]
                    result2 = subprocess.run(cmd2, capture_output=True, text=True, timeout=30)
                    return result2.returncode == 0
            return False
        except Exception as e:
            logger.debug(f"nmcli connect attempt failed: {e}")
            return False

    def _try_wpa_cli():
        try:
            # Find existing network id for SSID
            result = subprocess.run(
                ['sudo', 'wpa_cli', '-i', 'wlan0', 'list_networks'],
                capture_output=True,
                text=True,
                timeout=5
            )
            network_id = None
            if result.returncode == 0:
                for line in result.stdout.strip().split('\n')[1:]:
                    parts = line.split('\t')
                    if len(parts) >= 2 and parts[1] == ssid:
                        network_id = parts[0]
                        break

            if network_id is None:
                # Create a new network
                add = subprocess.run(['sudo', 'wpa_cli', '-i', 'wlan0', 'add_network'],
                                     capture_output=True, text=True, timeout=5)
                if add.returncode != 0 or not add.stdout.strip().isdigit():
                    return
                network_id = add.stdout.strip()
                subprocess.run(['sudo', 'wpa_cli', '-i', 'wlan0', 'set_network', network_id, 'ssid', f"\"{ssid}\""],
                               capture_output=True, text=True, timeout=5)
                if password:
                    # wpa_cli accepts either a quoted passphrase OR a raw 64-hex PSK.
                    is_hex_psk = (len(password) == 64 and all(c in "0123456789abcdefABCDEF" for c in password))
                    psk_value = password if is_hex_psk else f"\"{password}\""
                    subprocess.run(['sudo', 'wpa_cli', '-i', 'wlan0', 'set_network', network_id, 'psk', psk_value],
                                   capture_output=True, text=True, timeout=5)
                else:
                    subprocess.run(['sudo', 'wpa_cli', '-i', 'wlan0', 'set_network', network_id, 'key_mgmt', 'NONE'],
                                   capture_output=True, text=True, timeout=5)
                subprocess.run(['sudo', 'wpa_cli', '-i', 'wlan0', 'set_network', network_id, 'priority', '20'],
                               capture_output=True, text=True, timeout=5)
                subprocess.run(['sudo', 'wpa_cli', '-i', 'wlan0', 'save_config'],
                               capture_output=True, text=True, timeout=5)

            # Select and reconnect
            subprocess.run(['sudo', 'wpa_cli', '-i', 'wlan0', 'enable_network', network_id],
                           capture_output=True, text=True, timeout=5)
            subprocess.run(['sudo', 'wpa_cli', '-i', 'wlan0', 'select_network', network_id],
                           capture_output=True, text=True, timeout=5)
            subprocess.run(['sudo', 'wpa_cli', '-i', 'wlan0', 'reconnect'],
                           capture_output=True, text=True, timeout=5)
        except Exception as e:
            logger.debug(f"wpa_cli connect attempt failed: {e}")

    # Kick off an initial connect attempt
    if wifi_manager == 'networkmanager':
        ensure_networkmanager_wifi_ready()
        _try_nmcli()
    else:
        _try_wpa_cli()

    # Poll connection state up to timeout
    while time.time() - start < timeout_seconds:
        if is_wifi_connected():
            logger.info(f"Connected to WiFi '{ssid}'")
            persist_last_wifi_credentials(ssid)
            clear_force_ap_flag()
            return True
        time.sleep(3)

    logger.warning(f"Failed to connect to '{ssid}' within {timeout_seconds}s")
    return False


def is_wifi_connected():
    """Check if WiFi is connected and has internet connectivity"""
    try:
        # Check if wlan0 is up and has an IP address
        result = subprocess.run(
            ['ip', 'addr', 'show', 'wlan0'],
            capture_output=True,
            text=True,
            timeout=5
        )
        
        if result.returncode != 0:
            logger.debug("wlan0 interface not found")
            return False
        
        # Check if we have an IP address (not just link-local)
        if 'inet ' not in result.stdout:
            logger.debug("No IP address on wlan0")
            return False
        
        # Check if we're connected to a WiFi network
        result = subprocess.run(
            ['iwgetid', '-r'],
            capture_output=True,
            text=True,
            timeout=5
        )
        
        if result.returncode != 0 or not result.stdout.strip():
            logger.debug("Not connected to any WiFi network")
            return False
        
        ssid = result.stdout.strip()
        logger.debug(f"Connected to WiFi: {ssid}")
        # Record last connected SSID + password (best-effort)
        persist_last_wifi_credentials(ssid)
        
        # Optional: Test internet connectivity
        try:
            result = subprocess.run(
                ['ping', '-c', '1', '-W', '2', '8.8.8.8'],
                capture_output=True,
                timeout=5
            )
            if result.returncode == 0:
                logger.debug("Internet connectivity confirmed")
                return True
            else:
                logger.debug("No internet connectivity, but WiFi connected")
                return True  # Still consider connected even without internet
        except:
            logger.debug("Ping test failed, but WiFi appears connected")
            return True
            
    except Exception as e:
        logger.error(f"Error checking WiFi status: {e}")
        return False


def is_configured_wifi_available():
    """Scan for available WiFi networks and check if any configured network is available"""
    global wifi_manager
    
    try:
        configured_networks = []
        
        if wifi_manager == 'networkmanager':
            # Get list of configured networks from NetworkManager
            result = subprocess.run(
                ['nmcli', '-t', '-f', 'NAME', 'connection', 'show'],
                capture_output=True,
                text=True,
                timeout=5
            )
            
            if result.returncode == 0:
                for line in result.stdout.strip().split('\n'):
                    if line and line != 'lo':  # Skip empty lines and loopback
                        configured_networks.append(line)
            
            if not configured_networks:
                logger.info("No configured WiFi networks found (NetworkManager)")
                return False
            
            # Rescan for networks
            subprocess.run(
                ['nmcli', 'device', 'wifi', 'rescan'],
                capture_output=True,
                timeout=10
            )
            time.sleep(2)
            
            # Get list of available networks
            result = subprocess.run(
                ['nmcli', '-t', '-f', 'SSID', 'device', 'wifi', 'list'],
                capture_output=True,
                text=True,
                timeout=10
            )
            
            if result.returncode != 0:
                logger.warning("WiFi scan failed (NetworkManager)")
                return False
            
            available_networks = [line.strip() for line in result.stdout.split('\n') if line.strip()]
            
            # Check if any configured network is available
            for ssid in configured_networks:
                if ssid in available_networks:
                    logger.info(f"Configured network '{ssid}' is available (NetworkManager)")
                    return True
            
            logger.debug("No configured networks in range (NetworkManager)")
            return False
            
        else:
            # wpa_supplicant method
            # Trigger a scan
            subprocess.run(
                ['sudo', 'iwlist', 'wlan0', 'scan'],
                capture_output=True,
                timeout=10
            )
            
            # Get list of configured networks from wpa_supplicant
            result = subprocess.run(
                ['sudo', 'wpa_cli', '-i', 'wlan0', 'list_networks'],
                capture_output=True,
                text=True,
                timeout=5
            )
            
            if result.returncode != 0:
                logger.warning("Could not list configured networks")
                return False
            
            # Parse configured networks (skip header line)
            for line in result.stdout.strip().split('\n')[1:]:
                parts = line.split('\t')
                if len(parts) >= 2:
                    configured_networks.append(parts[1])  # SSID is second column
            
            if not configured_networks:
                logger.info("No configured WiFi networks found")
                return False
            
            # Scan for available networks
            result = subprocess.run(
                ['sudo', 'iwlist', 'wlan0', 'scan'],
                capture_output=True,
                text=True,
                timeout=10
            )
            
            if result.returncode != 0:
                logger.warning("WiFi scan failed")
                return False
            
            # Check if any configured network is available
            for ssid in configured_networks:
                if f'ESSID:"{ssid}"' in result.stdout:
                    logger.info(f"Configured network '{ssid}' is available")
                    return True
            
            logger.debug("No configured networks in range")
            return False
        
    except Exception as e:
        logger.error(f"Error scanning for WiFi networks: {e}")
        return False


def switch_to_ap_mode():
    """Switch to Access Point mode"""
    global current_mode, wifi_manager, ovbuddy_was_active_before_ap
    
    logger.info("Switching to Access Point mode...")
    
    try:
        ap_config = get_ap_config()
        
        if not ap_config['enabled']:
            logger.info("AP fallback is disabled in configuration")
            return False
        
        # Stop services that might interfere
        logger.info("Stopping network services...")
        
        if wifi_manager == 'networkmanager':
            # Stop NetworkManager from managing wlan0
            logger.info("Setting wlan0 to unmanaged in NetworkManager...")
            subprocess.run(['sudo', 'nmcli', 'device', 'set', 'wlan0', 'managed', 'no'], timeout=10)
            subprocess.run(['sudo', 'nmcli', 'radio', 'wifi', 'off'], timeout=5)
            time.sleep(2)
            subprocess.run(['sudo', 'nmcli', 'radio', 'wifi', 'on'], timeout=5)
            time.sleep(1)
        else:
            # Stop wpa_supplicant and dhcpcd
            subprocess.run(['sudo', 'systemctl', 'stop', 'wpa_supplicant'], timeout=10)
            subprocess.run(['sudo', 'systemctl', 'stop', 'dhcpcd'], timeout=10)
        
        # Kill any existing hostapd and dnsmasq
        subprocess.run(['sudo', 'killall', 'hostapd'], capture_output=True)
        subprocess.run(['sudo', 'killall', 'dnsmasq'], capture_output=True)
        time.sleep(2)
        
        # Configure wlan0 with static IP
        logger.info("Configuring wlan0 with static IP...")
        subprocess.run(['sudo', 'ip', 'addr', 'flush', 'dev', 'wlan0'], timeout=5)
        subprocess.run(['sudo', 'ip', 'link', 'set', 'wlan0', 'down'], timeout=5)
        subprocess.run(['sudo', 'ip', 'addr', 'add', '192.168.4.1/24', 'dev', 'wlan0'], timeout=5)
        subprocess.run(['sudo', 'ip', 'link', 'set', 'wlan0', 'up'], timeout=5)
        
        # Create hostapd configuration
        hostapd_conf = f"""interface=wlan0
driver=nl80211
ssid={ap_config['ssid']}
hw_mode=g
channel=6
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
"""
        
        # Add WPA2 configuration if password is set
        if ap_config['password']:
            hostapd_conf += f"""wpa=2
wpa_passphrase={ap_config['password']}
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
"""
        
        # Write hostapd configuration
        hostapd_conf_file = '/tmp/hostapd_ovbuddy.conf'
        with open(hostapd_conf_file, 'w') as f:
            f.write(hostapd_conf)
        
        # Create dnsmasq configuration
        dnsmasq_conf = """interface=wlan0
dhcp-range=192.168.4.2,192.168.4.20,255.255.255.0,24h
domain=local
address=/ovbuddy.local/192.168.4.1
"""
        
        dnsmasq_conf_file = '/tmp/dnsmasq_ovbuddy.conf'
        with open(dnsmasq_conf_file, 'w') as f:
            f.write(dnsmasq_conf)
        
        # Start hostapd
        logger.info(f"Starting hostapd with SSID: {ap_config['ssid']}")
        hostapd_process = subprocess.Popen(
            ['sudo', 'hostapd', hostapd_conf_file],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        
        time.sleep(3)
        
        # Check if hostapd started successfully
        if hostapd_process.poll() is not None:
            stdout, stderr = hostapd_process.communicate()
            logger.error(f"hostapd failed to start: {stderr.decode()}")
            return False
        
        # Start dnsmasq
        logger.info("Starting dnsmasq...")
        subprocess.run(
            ['sudo', 'dnsmasq', '-C', dnsmasq_conf_file, '-d', '--log-facility=-'],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True
        )
        
        time.sleep(2)
        
        current_mode = 'ap'
        password_info = "open network" if not ap_config['password'] else "with password"
        logger.info(f"Access Point mode active: SSID '{ap_config['ssid']}' ({password_info})")
        logger.info("Web interface available at http://192.168.4.1:8080")
        
        # Display AP information on e-ink screen
        try:
            # Stop the main display service to avoid two processes driving the e-ink at once.
            # (ovbuddy.service writes to the same SPI/GPIO/display.)
            ovbuddy_was_active_before_ap = False
            try:
                status = subprocess.run(
                    ['systemctl', 'is-active', 'ovbuddy'],
                    capture_output=True,
                    text=True,
                    timeout=3
                )
                if status.returncode == 0 and status.stdout.strip() == 'active':
                    ovbuddy_was_active_before_ap = True
                    logger.info("Stopping ovbuddy service to show AP info on the display...")
                    subprocess.run(['systemctl', 'stop', 'ovbuddy'], timeout=10)
            except Exception as e:
                logger.warning(f"Could not stop ovbuddy service before displaying AP info: {e}")

            logger.info("Displaying AP information on e-ink screen...")
            script_dir = os.path.dirname(os.path.abspath(__file__))
            display_script = os.path.join(script_dir, 'display_ap_info.py')
            
            if os.path.exists(display_script):
                result = subprocess.run(
                    ['python3', display_script],
                    capture_output=True,
                    text=True,
                    timeout=30
                )
                
                if result.returncode == 0:
                    logger.info("AP information displayed on screen")
                else:
                    logger.warning(f"Failed to display AP info: {result.stderr}")
            else:
                logger.warning(f"Display script not found: {display_script}")
        except Exception as e:
            logger.error(f"Error displaying AP info on screen: {e}")
            # Don't fail AP mode if display fails
        
        return True
        
    except Exception as e:
        logger.error(f"Error switching to AP mode: {e}")
        import traceback
        traceback.print_exc()
        return False


def switch_to_client_mode():
    """Switch back to WiFi client mode"""
    global current_mode, disconnect_start_time, wifi_manager, ovbuddy_was_active_before_ap
    
    logger.info("Switching to WiFi client mode...")
    
    try:
        # Stop AP services
        logger.info("Stopping AP services...")
        subprocess.run(['sudo', 'killall', 'hostapd'], capture_output=True)
        subprocess.run(['sudo', 'killall', 'dnsmasq'], capture_output=True)
        time.sleep(2)
        
        # Flush IP configuration
        subprocess.run(['sudo', 'ip', 'addr', 'flush', 'dev', 'wlan0'], timeout=5)
        subprocess.run(['sudo', 'ip', 'link', 'set', 'wlan0', 'down'], timeout=5)
        time.sleep(1)
        
        # Restart network services
        logger.info("Restarting network services...")
        
        if wifi_manager == 'networkmanager':
            # Re-enable NetworkManager management of wlan0
            logger.info("Re-enabling NetworkManager management of wlan0...")
            subprocess.run(['sudo', 'nmcli', 'device', 'set', 'wlan0', 'managed', 'yes'], timeout=10)
            subprocess.run(['sudo', 'nmcli', 'radio', 'wifi', 'off'], timeout=5)
            time.sleep(2)
            subprocess.run(['sudo', 'nmcli', 'radio', 'wifi', 'on'], timeout=5)
            time.sleep(3)
            
            # Re-enable auto-connect for all WiFi connections
            logger.info("Re-enabling auto-connect for WiFi connections...")
            result = subprocess.run(
                ['sudo', 'nmcli', '-t', '-f', 'NAME,TYPE', 'connection', 'show'],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0:
                for line in result.stdout.strip().split('\n'):
                    if ':802-11-wireless' in line:
                        conn_name = line.split(':')[0]
                        logger.info(f"Enabling auto-connect for: {conn_name}")
                        subprocess.run(
                            ['sudo', 'nmcli', 'connection', 'modify', conn_name, 'connection.autoconnect', 'yes'],
                            timeout=5,
                            capture_output=True
                        )
            
            # Trigger connection to known networks
            subprocess.run(['sudo', 'nmcli', 'device', 'connect', 'wlan0'], timeout=10, capture_output=True)
        else:
            # Restart wpa_supplicant and dhcpcd
            subprocess.run(['sudo', 'systemctl', 'start', 'dhcpcd'], timeout=10)
            subprocess.run(['sudo', 'systemctl', 'start', 'wpa_supplicant'], timeout=10)
            
            # Bring interface up
            subprocess.run(['sudo', 'ip', 'link', 'set', 'wlan0', 'up'], timeout=5)
            
            # Re-enable all networks
            logger.info("Re-enabling all WiFi networks...")
            subprocess.run(['sudo', 'wpa_cli', '-i', 'wlan0', 'enable_network', 'all'], timeout=5)
            
            # Trigger wpa_supplicant to reconnect
            subprocess.run(['sudo', 'wpa_cli', '-i', 'wlan0', 'reconfigure'], timeout=5)
        
        time.sleep(5)
        
        current_mode = 'client'
        disconnect_start_time = None
        logger.info("Client mode restored")

        # If we stopped ovbuddy to show AP info, bring it back once client mode is restored.
        if ovbuddy_was_active_before_ap:
            try:
                logger.info("Restarting ovbuddy service after leaving AP mode...")
                subprocess.run(['systemctl', 'start', 'ovbuddy'], timeout=10)
            except Exception as e:
                logger.warning(f"Could not restart ovbuddy service after AP mode: {e}")
            finally:
                ovbuddy_was_active_before_ap = False
        
        return True
        
    except Exception as e:
        logger.error(f"Error switching to client mode: {e}")
        import traceback
        traceback.print_exc()
        return False


def main():
    """Main monitoring loop"""
    global current_mode, disconnect_start_time, running, wifi_manager
    
    # Register signal handlers
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    logger.info("OVBuddy WiFi Monitor started")
    logger.info(f"Check interval: {CHECK_INTERVAL}s")
    logger.info(f"Disconnect threshold: {DISCONNECT_THRESHOLD}s")
    
    # Detect WiFi manager
    wifi_manager = detect_wifi_manager()
    logger.info(f"WiFi manager detected: {wifi_manager}")
    if wifi_manager == 'networkmanager':
        # Restore sane defaults in case force-ap-mode.sh disabled them previously.
        ensure_networkmanager_wifi_ready()
    
    # Check if force AP mode flag exists
    force_ap_requested = os.path.exists(FORCE_AP_FLAG)
    if force_ap_requested:
        logger.info("Force AP mode flag detected, entering AP mode immediately")
        # Remove the flag file
        try:
            os.remove(FORCE_AP_FLAG)
            logger.info("Removed force AP flag file")
        except Exception as e:
            logger.warning(f"Could not remove force AP flag: {e}")
        
        # Enter AP mode immediately
        current_mode = 'client'  # Start in client mode so switch_to_ap_mode works
        if switch_to_ap_mode():
            logger.info("Successfully entered forced AP mode")
        else:
            logger.error("Failed to enter forced AP mode, continuing with normal operation")
            # Determine initial mode normally
            if is_wifi_connected():
                current_mode = 'client'
                logger.info("Starting in client mode (WiFi connected)")
            else:
                logger.info("WiFi not connected at startup")
                disconnect_start_time = time.time()
                current_mode = 'client'
    else:
        # Determine initial mode normally, but on boot:
        # - If last_wifi_ssid is known, give it up to BOOT_CONNECT_TIMEOUT seconds to reconnect
        # - Only then fall back to AP mode
        if is_wifi_connected():
            current_mode = 'client'
            logger.info("Starting in client mode (WiFi connected)")
            clear_force_ap_flag()
        else:
            boot_wifi = get_last_wifi_config()
            if boot_wifi.get("ssid"):
                global boot_connect_deadline, boot_last_wifi
                boot_last_wifi = boot_wifi
                boot_connect_deadline = time.time() + BOOT_CONNECT_TIMEOUT
                pwd_present = bool(boot_wifi.get("password"))
                logger.info(
                    f"WiFi not connected at startup. Will try last-known WiFi '{boot_wifi['ssid']}' "
                    f"for up to {BOOT_CONNECT_TIMEOUT}s before AP fallback."
                )
                logger.info(f"Last-known WiFi password present: {pwd_present}")
                # Kick off a best-effort connect attempt (non-blocking for the rest of the logic)
                try:
                    attempt_connect_to_last_wifi(boot_wifi["ssid"], boot_wifi.get("password", ""), timeout_seconds=10)
                except Exception as e:
                    logger.debug(f"Initial boot connect kick failed: {e}")

                disconnect_start_time = time.time()
                current_mode = 'client'
            else:
                logger.info("WiFi not connected at startup (no last-known WiFi saved)")
                disconnect_start_time = time.time()
                current_mode = 'client'
    
    while running:
        try:
            if current_mode == 'client':
                # Client mode: monitor WiFi connection
                if is_wifi_connected():
                    # Ensure force-AP is one-shot: clear any lingering flag when WiFi is healthy.
                    clear_force_ap_flag()
                    # If we were in boot reconnect grace period, clear it.
                    if boot_connect_deadline is not None:
                        logger.info("Boot reconnect succeeded; clearing boot reconnect grace period")
                        boot_connect_deadline = None
                        boot_last_wifi = None
                    # WiFi is connected, reset disconnect timer
                    if disconnect_start_time is not None:
                        logger.info("WiFi connection restored")
                        disconnect_start_time = None
                else:
                    # WiFi is disconnected
                    if disconnect_start_time is None:
                        logger.warning("WiFi disconnected")
                        disconnect_start_time = time.time()
                    else:
                        # Check if we've been disconnected long enough
                        disconnect_duration = time.time() - disconnect_start_time
                        logger.info(f"WiFi disconnected for {int(disconnect_duration)}s")
                        
                        # Boot reconnect grace: don't enter AP until deadline passes
                        if boot_connect_deadline is not None:
                            remaining = int(max(0, boot_connect_deadline - time.time()))
                            if remaining > 0:
                                logger.info(f"Boot reconnect grace active: {remaining}s remaining before AP fallback")
                                if wifi_manager == 'networkmanager':
                                    ensure_networkmanager_wifi_ready()
                                # Periodically re-kick connection attempt during boot grace
                                if boot_last_wifi and (int(disconnect_duration) % 15 == 0):
                                    try:
                                        attempt_connect_to_last_wifi(
                                            boot_last_wifi.get("ssid", ""),
                                            boot_last_wifi.get("password", ""),
                                            timeout_seconds=10
                                        )
                                    except Exception:
                                        pass
                                time.sleep(CHECK_INTERVAL)
                                continue
                            else:
                                logger.warning("Boot reconnect grace expired; entering AP mode")
                                boot_connect_deadline = None
                                boot_last_wifi = None
                                if switch_to_ap_mode():
                                    disconnect_start_time = None
                                else:
                                    logger.error("Failed to switch to AP mode after boot grace expiry, will retry")
                                    time.sleep(30)
                                time.sleep(CHECK_INTERVAL)
                                continue

                        if disconnect_duration >= DISCONNECT_THRESHOLD:
                            logger.warning(f"WiFi disconnected for {int(disconnect_duration)}s, switching to AP mode")
                            if switch_to_ap_mode():
                                disconnect_start_time = None
                            else:
                                logger.error("Failed to switch to AP mode, will retry")
                                time.sleep(30)
                
                time.sleep(CHECK_INTERVAL)
                
            elif current_mode == 'ap':
                # AP mode: periodically check if configured WiFi is available
                logger.info("In AP mode, checking for configured WiFi networks...")
                
                if is_configured_wifi_available():
                    logger.info("Configured WiFi network detected, switching back to client mode")
                    if switch_to_client_mode():
                        # Give it time to connect
                        time.sleep(10)
                        if is_wifi_connected():
                            logger.info("Successfully reconnected to WiFi")
                            clear_force_ap_flag()
                        else:
                            logger.warning("Switched to client mode but not connected yet")
                    else:
                        logger.error("Failed to switch to client mode")
                else:
                    logger.info("No configured WiFi networks available, staying in AP mode")
                
                time.sleep(AP_CHECK_INTERVAL)
                
        except Exception as e:
            logger.error(f"Error in main loop: {e}")
            import traceback
            traceback.print_exc()
            time.sleep(CHECK_INTERVAL)
    
    logger.info("WiFi monitor stopped")


if __name__ == "__main__":
    main()

