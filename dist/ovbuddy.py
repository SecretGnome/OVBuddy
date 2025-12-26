#!/usr/bin/env python3
import time
import requests
import sys
import os
import signal
import re
import argparse
import json
import threading
import io
import socket
import subprocess
import uuid
from datetime import datetime, timedelta

# Optional imports for web server
try:
    from flask import Flask, request, jsonify, render_template
    FLASK_AVAILABLE = True
except ImportError:
    FLASK_AVAILABLE = False
    print("Warning: Flask not available. Web server will not start.")
    print("  To install: pip3 install flask")

try:
    from zeroconf import ServiceInfo, Zeroconf
    ZEROCONF_AVAILABLE = True
except ImportError:
    ZEROCONF_AVAILABLE = False
    print("Warning: zeroconf not available. Bonjour service will not be available.")
    print("  To install: pip3 install zeroconf")

# Optional imports for QR code
try:
    import pyqrcode
    QRCODE_AVAILABLE = True
except ImportError:
    QRCODE_AVAILABLE = False
    print("Warning: pyqrcode not available. QR code will not be displayed.")
    print("  To install: pip3 install pyqrcode pypng")

# Check if requirements.txt exists and suggest installation
if not FLASK_AVAILABLE or not ZEROCONF_AVAILABLE:
    script_dir = os.path.dirname(os.path.abspath(__file__))
    requirements_file = os.path.join(script_dir, "requirements.txt")
    if os.path.exists(requirements_file):
        print(f"  To install all dependencies: pip3 install -r {requirements_file}")

# Test mode: set TEST_MODE=1 environment variable to run without display hardware
TEST_MODE = os.getenv("TEST_MODE", "0") == "1"

if not TEST_MODE:
    from PIL import Image, ImageDraw, ImageFont
    import epd2in13_V4  # local file in the same folder

# --------------------------
# VERSION
# --------------------------
VERSION = "0.0.9"

# --------------------------
# CONFIGURATION
# --------------------------
CONFIG_FILE = "config.json"
CONFIG_LOCK = threading.Lock()
CONFIG_LAST_MODIFIED = 0

# Default configuration values (used as fallback)
DEFAULT_CONFIG = {
    "stations": ["Zürich Saalsporthalle", "Zürich, Saalsporthalle"],
    "lines": ["S4", "T13", "T5"],
    "refresh_interval": 20,
    "qr_code_display_duration": 10,
    "destination_prefixes_to_remove": ["Zurich ", "Zurich, ", "Zuerich ", "Zuerich, ", "Zürich ", "Zürich, "],
    "destination_exceptions": ["HB", "Hbf"],
    "inverted": False,
    "max_departures": 6,
    "flip_display": False,
    "use_partial_refresh": False,
    "update_repository_url": "https://github.com/tenineight/OVBuddy",
    "auto_update": False,
    "ap_fallback_enabled": True,
    "ap_ssid": "OVBuddy",
    "ap_password": "password",
    "display_ap_password": True,
    # Last-known WiFi (used by wifi-monitor on boot to attempt reconnect before AP fallback)
    "last_wifi_ssid": "",
    "last_wifi_password": ""
}

# Configuration variables (will be loaded from config.json)
STATIONS = DEFAULT_CONFIG["stations"]
LINES = DEFAULT_CONFIG["lines"]
REFRESH_INTERVAL = DEFAULT_CONFIG["refresh_interval"]
QR_CODE_DISPLAY_DURATION = DEFAULT_CONFIG["qr_code_display_duration"]
DESTINATION_PREFIXES_TO_REMOVE = DEFAULT_CONFIG["destination_prefixes_to_remove"]
DESTINATION_EXCEPTIONS = DEFAULT_CONFIG["destination_exceptions"]
INVERTED = DEFAULT_CONFIG["inverted"]
MAX_DEPARTURES = DEFAULT_CONFIG["max_departures"]
FLIP_DISPLAY = DEFAULT_CONFIG["flip_display"]
USE_PARTIAL_REFRESH = DEFAULT_CONFIG["use_partial_refresh"]
UPDATE_REPOSITORY_URL = DEFAULT_CONFIG["update_repository_url"]
AUTO_UPDATE = DEFAULT_CONFIG["auto_update"]
AP_FALLBACK_ENABLED = DEFAULT_CONFIG["ap_fallback_enabled"]
AP_SSID = DEFAULT_CONFIG["ap_ssid"]
AP_PASSWORD = DEFAULT_CONFIG["ap_password"]
DISPLAY_AP_PASSWORD = DEFAULT_CONFIG["display_ap_password"]
LAST_WIFI_SSID = DEFAULT_CONFIG["last_wifi_ssid"]
LAST_WIFI_PASSWORD = DEFAULT_CONFIG["last_wifi_password"]

# Display constants (not configurable via web)
DISPLAY_WIDTH = 250
DISPLAY_HEIGHT = 122

# --------------------------
# CONFIGURATION FUNCTIONS
# --------------------------
def load_config():
    """Load configuration from config.json file"""
    global STATIONS, LINES, REFRESH_INTERVAL, QR_CODE_DISPLAY_DURATION
    global DESTINATION_PREFIXES_TO_REMOVE, DESTINATION_EXCEPTIONS
    global INVERTED, MAX_DEPARTURES, FLIP_DISPLAY, USE_PARTIAL_REFRESH, UPDATE_REPOSITORY_URL, AUTO_UPDATE
    global AP_FALLBACK_ENABLED, AP_SSID, AP_PASSWORD, DISPLAY_AP_PASSWORD
    global LAST_WIFI_SSID, LAST_WIFI_PASSWORD
    global CONFIG_LAST_MODIFIED
    
    with CONFIG_LOCK:
        config_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), CONFIG_FILE)
        
        # Check if config file exists
        if not os.path.exists(config_path):
            print(f"Config file not found, using defaults and creating {CONFIG_FILE}")
            save_config()  # Create config file with defaults
            return
        
        try:
            # Check modification time
            mtime = os.path.getmtime(config_path)
            if mtime == CONFIG_LAST_MODIFIED:
                return  # No changes, skip reload
            CONFIG_LAST_MODIFIED = mtime
            
            with open(config_path, 'r', encoding='utf-8') as f:
                config = json.load(f)
            
            # Validate and load configuration
            STATIONS = config.get("stations", DEFAULT_CONFIG["stations"])
            LINES = config.get("lines", DEFAULT_CONFIG["lines"])
            REFRESH_INTERVAL = max(1, int(config.get("refresh_interval", DEFAULT_CONFIG["refresh_interval"])))
            QR_CODE_DISPLAY_DURATION = max(0, int(config.get("qr_code_display_duration", DEFAULT_CONFIG["qr_code_display_duration"])))
            DESTINATION_PREFIXES_TO_REMOVE = config.get("destination_prefixes_to_remove", DEFAULT_CONFIG["destination_prefixes_to_remove"])
            DESTINATION_EXCEPTIONS = config.get("destination_exceptions", DEFAULT_CONFIG["destination_exceptions"])
            INVERTED = bool(config.get("inverted", DEFAULT_CONFIG["inverted"]))
            MAX_DEPARTURES = max(1, min(20, int(config.get("max_departures", DEFAULT_CONFIG["max_departures"]))))
            FLIP_DISPLAY = bool(config.get("flip_display", DEFAULT_CONFIG["flip_display"]))
            USE_PARTIAL_REFRESH = bool(config.get("use_partial_refresh", DEFAULT_CONFIG["use_partial_refresh"]))
            UPDATE_REPOSITORY_URL = config.get("update_repository_url", DEFAULT_CONFIG["update_repository_url"])
            AUTO_UPDATE = bool(config.get("auto_update", DEFAULT_CONFIG["auto_update"]))
            AP_FALLBACK_ENABLED = bool(config.get("ap_fallback_enabled", DEFAULT_CONFIG["ap_fallback_enabled"]))
            AP_SSID = str(config.get("ap_ssid", DEFAULT_CONFIG["ap_ssid"]))
            AP_PASSWORD = str(config.get("ap_password", DEFAULT_CONFIG["ap_password"]))
            DISPLAY_AP_PASSWORD = bool(config.get("display_ap_password", DEFAULT_CONFIG["display_ap_password"]))
            LAST_WIFI_SSID = str(config.get("last_wifi_ssid", DEFAULT_CONFIG["last_wifi_ssid"]))
            LAST_WIFI_PASSWORD = str(config.get("last_wifi_password", DEFAULT_CONFIG["last_wifi_password"]))
            
            print(f"Configuration loaded from {CONFIG_FILE}")
        except json.JSONDecodeError as e:
            print(f"Error parsing {CONFIG_FILE}: {e}. Using defaults.")
        except Exception as e:
            print(f"Error loading {CONFIG_FILE}: {e}. Using defaults.")

def save_config():
    """Save current configuration to config.json file"""
    config_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), CONFIG_FILE)
    
    with CONFIG_LOCK:
        config = {
            "stations": STATIONS,
            "lines": LINES,
            "refresh_interval": REFRESH_INTERVAL,
            "qr_code_display_duration": QR_CODE_DISPLAY_DURATION,
            "destination_prefixes_to_remove": DESTINATION_PREFIXES_TO_REMOVE,
            "destination_exceptions": DESTINATION_EXCEPTIONS,
            "inverted": INVERTED,
            "max_departures": MAX_DEPARTURES,
            "flip_display": FLIP_DISPLAY,
            "use_partial_refresh": USE_PARTIAL_REFRESH,
            "update_repository_url": UPDATE_REPOSITORY_URL,
            "ap_fallback_enabled": AP_FALLBACK_ENABLED,
            "ap_ssid": AP_SSID,
            "ap_password": AP_PASSWORD,
            "display_ap_password": DISPLAY_AP_PASSWORD,
            "auto_update": AUTO_UPDATE,
            "last_wifi_ssid": LAST_WIFI_SSID,
            "last_wifi_password": LAST_WIFI_PASSWORD
        }
        
        try:
            with open(config_path, 'w', encoding='utf-8') as f:
                json.dump(config, f, indent=2, ensure_ascii=False)
            
            # Update modification time
            global CONFIG_LAST_MODIFIED
            CONFIG_LAST_MODIFIED = os.path.getmtime(config_path)
            
            print(f"Configuration saved to {CONFIG_FILE}")
            return True
        except Exception as e:
            print(f"Error saving {CONFIG_FILE}: {e}")
            return False

def get_config_dict():
    """Get current configuration as a dictionary (thread-safe)"""
    with CONFIG_LOCK:
        return {
            "stations": STATIONS,
            "lines": LINES,
            "refresh_interval": REFRESH_INTERVAL,
            "qr_code_display_duration": QR_CODE_DISPLAY_DURATION,
            "destination_prefixes_to_remove": DESTINATION_PREFIXES_TO_REMOVE,
            "destination_exceptions": DESTINATION_EXCEPTIONS,
            "inverted": INVERTED,
            "max_departures": MAX_DEPARTURES,
            "flip_display": FLIP_DISPLAY,
            "use_partial_refresh": USE_PARTIAL_REFRESH,
            "update_repository_url": UPDATE_REPOSITORY_URL,
            "auto_update": AUTO_UPDATE,
            "ap_fallback_enabled": AP_FALLBACK_ENABLED,
            "ap_ssid": AP_SSID,
            "ap_password": AP_PASSWORD,
            "display_ap_password": DISPLAY_AP_PASSWORD,
            "last_wifi_ssid": LAST_WIFI_SSID,
            "last_wifi_password": LAST_WIFI_PASSWORD
        }

def update_config(new_config):
    """Update configuration from a dictionary (thread-safe)"""
    global STATIONS, LINES, REFRESH_INTERVAL, QR_CODE_DISPLAY_DURATION
    global DESTINATION_PREFIXES_TO_REMOVE, DESTINATION_EXCEPTIONS
    global INVERTED, MAX_DEPARTURES, FLIP_DISPLAY, USE_PARTIAL_REFRESH, UPDATE_REPOSITORY_URL, AUTO_UPDATE
    global AP_FALLBACK_ENABLED, AP_SSID, AP_PASSWORD, DISPLAY_AP_PASSWORD
    global LAST_WIFI_SSID, LAST_WIFI_PASSWORD
    
    with CONFIG_LOCK:
        if "stations" in new_config:
            STATIONS = new_config["stations"] if isinstance(new_config["stations"], list) else [new_config["stations"]]
        if "lines" in new_config:
            LINES = new_config["lines"] if isinstance(new_config["lines"], list) else [new_config["lines"]]
        if "refresh_interval" in new_config:
            REFRESH_INTERVAL = max(1, int(new_config["refresh_interval"]))
        if "qr_code_display_duration" in new_config:
            QR_CODE_DISPLAY_DURATION = max(0, int(new_config["qr_code_display_duration"]))
        if "destination_prefixes_to_remove" in new_config:
            DESTINATION_PREFIXES_TO_REMOVE = new_config["destination_prefixes_to_remove"] if isinstance(new_config["destination_prefixes_to_remove"], list) else []
        if "destination_exceptions" in new_config:
            DESTINATION_EXCEPTIONS = new_config["destination_exceptions"] if isinstance(new_config["destination_exceptions"], list) else []
        if "inverted" in new_config:
            INVERTED = bool(new_config["inverted"])
        if "max_departures" in new_config:
            MAX_DEPARTURES = max(1, min(20, int(new_config["max_departures"])))
        if "flip_display" in new_config:
            FLIP_DISPLAY = bool(new_config["flip_display"])
        if "use_partial_refresh" in new_config:
            USE_PARTIAL_REFRESH = bool(new_config["use_partial_refresh"])
        if "update_repository_url" in new_config:
            UPDATE_REPOSITORY_URL = str(new_config["update_repository_url"])
        if "auto_update" in new_config:
            AUTO_UPDATE = bool(new_config["auto_update"])
        if "ap_fallback_enabled" in new_config:
            AP_FALLBACK_ENABLED = bool(new_config["ap_fallback_enabled"])
        if "ap_ssid" in new_config:
            AP_SSID = str(new_config["ap_ssid"])
        if "ap_password" in new_config:
            AP_PASSWORD = str(new_config["ap_password"])
        if "display_ap_password" in new_config:
            DISPLAY_AP_PASSWORD = bool(new_config["display_ap_password"])
        if "last_wifi_ssid" in new_config:
            LAST_WIFI_SSID = str(new_config["last_wifi_ssid"])
        if "last_wifi_password" in new_config:
            LAST_WIFI_PASSWORD = str(new_config["last_wifi_password"])
    
    return save_config()

# --------------------------
# VERSION CHECKING AND UPDATE FUNCTIONS
# --------------------------
def compare_versions(current, latest):
    """Compare two semantic version strings (e.g., '0.0.1', '0.1.0')
    Returns: 1 if latest > current, 0 if equal, -1 if current > latest
    """
    try:
        # Remove 'v' prefix if present
        current = current.lstrip('v')
        latest = latest.lstrip('v')
        
        # Split into parts and convert to integers
        current_parts = [int(x) for x in current.split('.')]
        latest_parts = [int(x) for x in latest.split('.')]
        
        # Pad shorter version with zeros
        while len(current_parts) < len(latest_parts):
            current_parts.append(0)
        while len(latest_parts) < len(current_parts):
            latest_parts.append(0)
        
        # Compare each part
        for c, l in zip(current_parts, latest_parts):
            if l > c:
                return 1
            elif l < c:
                return -1
        
        return 0
    except Exception as e:
        print(f"Error comparing versions '{current}' vs '{latest}': {e}")
        import traceback
        traceback.print_exc()
        # Return 0 (equal) on error, which means no update available
        # This is safer than returning 1 (update available) on error
        return 0

def get_latest_version_from_github(repo_url):
    """Fetch the latest version tag from GitHub repository
    Returns: version string (e.g., '0.0.1') or None if error
    """
    try:
        # Parse repository URL to get owner and repo name
        # Expected formats:
        # - https://github.com/owner/repo
        # - https://github.com/owner/repo.git
        # - github.com/owner/repo
        
        repo_url = repo_url.rstrip('/')
        if repo_url.endswith('.git'):
            repo_url = repo_url[:-4]
        
        # Extract owner and repo from URL
        parts = repo_url.replace('https://', '').replace('http://', '').split('/')
        if len(parts) < 3 or parts[0] != 'github.com':
            print(f"Invalid GitHub repository URL: {repo_url}")
            return None
        
        owner = parts[1]
        repo = parts[2]
        
        # Fetch tags from GitHub API
        api_url = f"https://api.github.com/repos/{owner}/{repo}/tags"
        print(f"Checking for updates at: {api_url}")
        
        response = requests.get(api_url, timeout=10)
        if response.status_code != 200:
            print(f"GitHub API returned status {response.status_code}")
            return None
        
        tags = response.json()
        if not tags or len(tags) == 0:
            print("No tags found in repository")
            return None
        
        # Sort tags by version number (not alphabetically)
        # GitHub API may return tags in different orders
        def get_version_key(tag_name):
            """Extract version for sorting"""
            try:
                # Remove 'v' prefix if present
                version_str = tag_name.lstrip('v')
                # Split and convert to tuple of integers for proper sorting
                parts = [int(x) for x in version_str.split('.')]
                # Pad with zeros to handle different lengths (e.g., 0.0.4 vs 0.0.5)
                while len(parts) < 3:
                    parts.append(0)
                return tuple(parts)
            except:
                # If parsing fails, return a tuple that sorts last
                return (0, 0, 0)
        
        # Sort tags by version (newest first)
        sorted_tags = sorted(tags, key=lambda t: get_version_key(t['name']), reverse=True)
        latest_tag = sorted_tags[0]['name']
        print(f"Latest version on GitHub: {latest_tag}")
        
        return latest_tag
    
    except requests.exceptions.Timeout:
        print("GitHub API request timed out")
        return None
    except requests.exceptions.RequestException as e:
        print(f"Error fetching version from GitHub: {e}")
        return None
    except Exception as e:
        print(f"Unexpected error checking for updates: {e}")
        return None

def check_for_updates():
    """Check if a newer version is available on GitHub
    Returns: (update_available, latest_version) tuple
    """
    try:
        print(f"Current version: {VERSION}")
        print(f"Checking repository: {UPDATE_REPOSITORY_URL}")
        
        latest_version = get_latest_version_from_github(UPDATE_REPOSITORY_URL)
        if latest_version is None:
            print("Could not determine latest version")
            return (False, None)
        
        print(f"Comparing versions: '{VERSION}' vs '{latest_version}'")
        comparison = compare_versions(VERSION, latest_version)
        print(f"Comparison result: {comparison} (1=update available, 0=same, -1=current is newer)")
        
        if comparison > 0:
            print(f"Update available: {VERSION} -> {latest_version}")
            return (True, latest_version)
        elif comparison == 0:
            print(f"Already running the latest version ({VERSION})")
            return (False, latest_version)
        else:
            print(f"Running a newer version than GitHub ({VERSION} > {latest_version})")
            return (False, latest_version)
    
    except Exception as e:
        print(f"Error checking for updates: {e}")
        import traceback
        traceback.print_exc()
        return (False, None)

def get_file_version(file_path):
    """Extract version from a Python file by reading it
    Returns: version string or None if not found
    """
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            for line in f:
                # Look for VERSION = "x.x.x" pattern
                if 'VERSION' in line and '=' in line:
                    # Extract version string
                    match = re.search(r'["\']([0-9]+\.[0-9]+\.[0-9]+)["\']', line)
                    if match:
                        return match.group(1)
    except Exception:
        pass
    return None

def get_update_status():
    """Get current update status from status file
    Returns: dict with update status info
    """
    current_dir = os.path.dirname(os.path.abspath(__file__))
    status_file = os.path.join(current_dir, ".update_status.json")
    
    if not os.path.exists(status_file):
        return {
            "update_in_progress": False,
            "last_update_attempt": None,
            "last_update_version": None,
            "last_update_success": None
        }
    
    try:
        with open(status_file, 'r', encoding='utf-8') as f:
            return json.load(f)
    except Exception:
        return {
            "update_in_progress": False,
            "last_update_attempt": None,
            "last_update_version": None,
            "last_update_success": None
        }

def set_update_status(in_progress=False, version=None, success=None):
    """Update the update status file"""
    current_dir = os.path.dirname(os.path.abspath(__file__))
    status_file = os.path.join(current_dir, ".update_status.json")
    
    status = {
        "update_in_progress": in_progress,
        "last_update_attempt": datetime.now().isoformat() if in_progress or version else None,
        "last_update_version": version,
        "last_update_success": success
    }
    
    try:
        with open(status_file, 'w', encoding='utf-8') as f:
            json.dump(status, f, indent=2)
    except Exception as e:
        print(f"Warning: Could not write update status: {e}")

def perform_update(repo_url, target_version=None, epd=None, test_mode=False):
    """Perform system update by cloning repository and updating files
    
    Args:
        repo_url: GitHub repository URL
        target_version: Specific version to update to (tag name), or None for latest
        epd: EPD display object to show update progress (optional)
        test_mode: If True, don't try to use display
    
    Returns: True if update successful, False otherwise
    """
    import tempfile
    import shutil
    
    # Mark update as in progress
    set_update_status(in_progress=True, version=target_version, success=None)
    
    # Show initial update screen
    render_update_screen(epd, "Starting update...", target_version, test_mode)
    
    try:
        print("\n" + "="*50)
        print("PERFORMING SYSTEM UPDATE")
        print("="*50)
        
        # Get current directory
        current_dir = os.path.dirname(os.path.abspath(__file__))
        config_path = os.path.join(current_dir, CONFIG_FILE)
        
        # Check if git is available
        render_update_screen(epd, "Checking git...", target_version, test_mode)
        try:
            subprocess.run(['git', '--version'], capture_output=True, check=True, timeout=5)
        except (subprocess.CalledProcessError, FileNotFoundError, subprocess.TimeoutExpired):
            print("ERROR: git is not installed or not available")
            print("Please install git: sudo apt-get install git")
            render_update_screen(epd, "Error: git not found", target_version, test_mode)
            return False
        
        # Backup current config.json
        config_backup = None
        if os.path.exists(config_path):
            render_update_screen(epd, "Backing up config...", target_version, test_mode)
            print(f"Backing up {CONFIG_FILE}...")
            with open(config_path, 'r', encoding='utf-8') as f:
                config_backup = f.read()
            print("✓ Configuration backed up")
        
        # Create temporary directory for cloning
        with tempfile.TemporaryDirectory() as temp_dir:
            render_update_screen(epd, "Cloning repository...", target_version, test_mode)
            print(f"Cloning repository to temporary directory...")
            clone_path = os.path.join(temp_dir, "ovbuddy_update")
            
            # Clone repository
            clone_cmd = ['git', 'clone', '--depth', '1']
            if target_version:
                clone_cmd.extend(['--branch', target_version])
            clone_cmd.extend([repo_url, clone_path])
            
            print(f"Running: {' '.join(clone_cmd)}")
            result = subprocess.run(clone_cmd, capture_output=True, text=True, timeout=60)
            
            if result.returncode != 0:
                print(f"ERROR: Failed to clone repository")
                print(f"stdout: {result.stdout}")
                print(f"stderr: {result.stderr}")
                render_update_screen(epd, "Error: Clone failed", target_version, test_mode)
                return False
            
            print("✓ Repository cloned successfully")
            
            # Check if dist directory exists in cloned repo
            dist_path = os.path.join(clone_path, "dist")
            if not os.path.exists(dist_path):
                print(f"ERROR: dist/ directory not found in repository")
                render_update_screen(epd, "Error: No dist/ found", target_version, test_mode)
                return False
            
            render_update_screen(epd, "Updating files...", target_version, test_mode)
            print("Updating files from repository...")
            
            # Copy files from dist/ to current directory
            files_updated = 0
            for item in os.listdir(dist_path):
                src = os.path.join(dist_path, item)
                dst = os.path.join(current_dir, item)
                
                # Skip config.json - we'll restore it from backup
                if item == CONFIG_FILE:
                    continue
                
                try:
                    if os.path.isfile(src):
                        shutil.copy2(src, dst)
                        files_updated += 1
                        print(f"  ✓ Updated: {item}")
                    elif os.path.isdir(src):
                        # Remove existing directory if it exists
                        if os.path.exists(dst):
                            shutil.rmtree(dst)
                        shutil.copytree(src, dst)
                        files_updated += 1
                        print(f"  ✓ Updated: {item}/ (directory)")
                except Exception as e:
                    print(f"  ✗ Failed to update {item}: {e}")
            
            print(f"✓ Updated {files_updated} files/directories")
        
        # Restore config.json from backup
        if config_backup:
            render_update_screen(epd, "Restoring config...", target_version, test_mode)
            print(f"Restoring {CONFIG_FILE}...")
            with open(config_path, 'w', encoding='utf-8') as f:
                f.write(config_backup)
            print("✓ Configuration restored")
        
        render_update_screen(epd, "Update complete! Please restart device.", target_version, test_mode)
        print("\n" + "="*50)
        print("UPDATE COMPLETED SUCCESSFULLY")
        print("="*50)
        print("\nThe system needs to be restarted to apply changes...")
        
        # Mark update as successful
        set_update_status(in_progress=False, version=target_version, success=True)
        
        # Signal that restart is needed
        # We'll handle the actual restart in the main function
        return True
    
    except subprocess.TimeoutExpired:
        print("ERROR: Git operation timed out")
        set_update_status(in_progress=False, version=target_version, success=False)
        return False
    except Exception as e:
        print(f"ERROR: Update failed: {e}")
        set_update_status(in_progress=False, version=target_version, success=False)
        import traceback
        traceback.print_exc()
        return False

# --------------------------
# FUNCTIONS
# --------------------------
def normalize_line_number(line_str):
    """Normalize line number for comparison (e.g., 'S4' -> '4', '4' -> '4')"""
    if not line_str:
        return ""
    # Remove common prefixes and whitespace
    normalized = str(line_str).strip().upper()
    # Remove S, T, RE, IC, etc. prefixes
    prefixes = ['S', 'T', 'RE', 'IC', 'IR', 'EC', 'RJ']
    for prefix in prefixes:
        if normalized.startswith(prefix):
            normalized = normalized[len(prefix):].strip()
    return normalized

def matches_line(line_number, target_lines):
    """Check if a line number matches any of the target lines"""
    normalized = normalize_line_number(line_number)
    for target in target_lines:
        if normalize_line_number(target) == normalized:
            return True
    return False

def generate_mock_departures():
    """Generate mock departure data for testing"""
    now = datetime.now()
    
    # Create mock departures matching the requirements:
    # - S4 (train)
    # - 13 or 5 (tram)
    # - One with 2min delay
    # - One with 11min delay
    # Generate enough entries to test MAX_DEPARTURES (generate 10 to allow testing different values)
    mock_departures = [
        {
            "number": "4",
            "category": "S",
            "to": "Zürich, Bahnhofstrasse",
            "stop": {
                "departure": (now + timedelta(minutes=5)).strftime("%Y-%m-%dT%H:%M:%S+01:00"),
                "delay": 0  # No delay
            }
        },
        {
            "number": "13",
            "category": "T",
            "to": "Zürich, Seebacherplatz",
            "stop": {
                "departure": (now + timedelta(minutes=8)).strftime("%Y-%m-%dT%H:%M:%S+01:00"),
                "delay": 120  # 2 minutes delay (120 seconds)
            }
        },
        {
            "number": "5",
            "category": "T",
            "to": "Zürich, Laubegg",
            "stop": {
                "departure": (now + timedelta(minutes=12)).strftime("%Y-%m-%dT%H:%M:%S+01:00"),
                "delay": 660  # 11 minutes delay (660 seconds)
            }
        },
        {
            "number": "4",
            "category": "S",
            "to": "Zürich, Hauptbahnhof",
            "stop": {
                "departure": (now + timedelta(minutes=15)).strftime("%Y-%m-%dT%H:%M:%S+01:00"),
                "delay": 0  # No delay
            }
        },
        {
            "number": "13",
            "category": "T",
            "to": "Zürich, Seebacherplatz",
            "stop": {
                "departure": (now + timedelta(minutes=18)).strftime("%Y-%m-%dT%H:%M:%S+01:00"),
                "delay": 0  # No delay
            }
        },
        {
            "number": "5",
            "category": "T",
            "to": "Zürich, Laubegg",
            "stop": {
                "departure": (now + timedelta(minutes=22)).strftime("%Y-%m-%dT%H:%M:%S+01:00"),
                "delay": 0  # No delay
            }
        },
        {
            "number": "4",
            "category": "S",
            "to": "Zürich, Bahnhofstrasse",
            "stop": {
                "departure": (now + timedelta(minutes=25)).strftime("%Y-%m-%dT%H:%M:%S+01:00"),
                "delay": 0  # No delay
            }
        },
        {
            "number": "13",
            "category": "T",
            "to": "Zürich, Seebacherplatz",
            "stop": {
                "departure": (now + timedelta(minutes=28)).strftime("%Y-%m-%dT%H:%M:%S+01:00"),
                "delay": 0  # No delay
            }
        }
    ]
    
    return mock_departures

def fetch_departures(stations, limit=20):
    """Fetch upcoming departures from Swiss transport API for one or more stations"""
    all_departures = []
    
    # Ensure stations is a list
    if isinstance(stations, str):
        stations = [stations]
    
    for station in stations:
        url = "https://transport.opendata.ch/v1/stationboard"
        params = {"station": station, "limit": limit}
        try:
            data = requests.get(url, params=params, timeout=10).json()
            station_departures = data.get("stationboard", [])
            
            # Add station name to each departure for reference
            for dep in station_departures:
                dep["_station"] = station
            
            all_departures.extend(station_departures)
            
            # Debug: print what we got
            print(f"Station '{station}': {len(station_departures)} departures")
            if station_departures:
                print(f"  Available lines: {[d['number'] for d in station_departures[:10]]}")
                # Debug: show category info and delay info for first few departures
                for d in station_departures[:3]:
                    delay = d.get('stop', {}).get('delay', 0)
                    print(f"    Line {d.get('number')}: category={d.get('category')}, delay={delay}s")
        except Exception as e:
            error_msg = str(e)[:50]  # Truncate long error messages
            print(f"Error fetching departures from {station}: {e}")
            # Continue with other stations even if one fails
    
    if not all_departures:
        return [], "No departures found"
    
    print(f"Total departures fetched: {len(all_departures)}")
    print(f"Looking for lines: {LINES}")
    
    # Filter by lines
    filtered = [entry for entry in all_departures if matches_line(entry["number"], LINES)]
    
    # Sort by departure time
    filtered.sort(key=lambda x: x["stop"]["departure"])
    
    # If no filtered results but we have departures, return all (so user can see what's available)
    if not filtered and all_departures:
        print("No matches for selected lines, showing all departures")
        all_departures.sort(key=lambda x: x["stop"]["departure"])
        return all_departures, None
    
    return filtered, None

def format_line_number(entry):
    """Format line number to always be 3 characters, detecting tram vs train vs bus"""
    line_num = str(entry.get("number", "")).strip()
    category = str(entry.get("category", "")).upper()
    
    # Normalize line number to uppercase for processing
    line_upper = line_num.upper()
    
    # Detect transport type
    is_tram = category == "T" or "TRAM" in category
    is_bus = category == "B" or "BUS" in category
    is_train = category == "S" or "S-BAHN" in category or "TRAIN" in category
    
    # Extract the numeric part
    numeric_part = ""
    
    # Check if it already has a prefix
    if line_upper.startswith("S"):
        numeric_part = line_upper[1:].strip()  # Use uppercase version
        is_train = True  # Explicitly set as train
        is_tram = False
        is_bus = False
    elif line_upper.startswith("T"):
        # Remove T prefix to get just the number
        numeric_part = line_upper[1:].strip()  # Use uppercase version
        is_tram = True  # If it has T prefix, it's definitely a tram
        is_bus = False
        is_train = False
    else:
        # No prefix, use the whole thing as numeric part
        numeric_part = line_upper.strip()
        # Category determines the type
    
    # Ensure numeric part is 2 digits (pad with space if single digit)
    if len(numeric_part) == 1:
        numeric_part = numeric_part + " "
    elif len(numeric_part) == 0:
        numeric_part = "  "
    
    # Format based on type:
    # - Trains (S-Bahn): "S" + number
    # - Trams and Buses: just the number (no prefix)
    if is_train:
        result = ("S" + numeric_part[:2]).ljust(3)
    else:
        # Trams and buses: just show the number
        result = numeric_part[:2].ljust(3)
    
    return result

def safe_ascii(text):
    """Convert text to ASCII-safe string, replacing Unicode characters"""
    if not text:
        return ""
    # Replace common Unicode characters with ASCII equivalents
    replacements = {
        '→': '->',
        'ü': 'ue',
        'ö': 'oe',
        'ä': 'ae',
        'Ü': 'U',
        'Ö': 'Oe',
        'Ä': 'Ae',
        'é': 'e',
        'è': 'e',
        'ê': 'e',
        'à': 'a',
        'â': 'a',
        'ç': 'c',
    }
    result = text
    for unicode_char, ascii_char in replacements.items():
        result = result.replace(unicode_char, ascii_char)
    # Remove any remaining non-ASCII characters
    return result.encode('ascii', 'ignore').decode('ascii')

def clean_destination_name(dest):
    """Remove configured prefixes from destination name, except for exceptions"""
    if not dest:
        return dest
    
    result = dest.strip()
    result_lower = result.lower()
    
    # Build a regex pattern from all prefixes
    # Normalize prefixes and create a pattern that matches any of them
    prefix_patterns = []
    for prefix in DESTINATION_PREFIXES_TO_REMOVE:
        prefix_clean = prefix.strip()
        # Escape special regex characters and create case-insensitive pattern
        prefix_escaped = re.escape(prefix_clean)
        # Replace escaped spaces with \s* to handle variable spacing
        prefix_escaped = prefix_escaped.replace(r'\ ', r'\s+')
        prefix_patterns.append(prefix_escaped)
    
    # Create combined pattern: match any prefix at start, followed by optional comma/space
    if prefix_patterns:
        combined_pattern = '^(' + '|'.join(prefix_patterns) + r')\s*,?\s*'
        pattern = re.compile(combined_pattern, re.IGNORECASE)
        
        # Try to match and remove prefix
        match = pattern.match(result)
        if match:
            # Get what comes after the matched prefix
            after_prefix = result[match.end():].strip()
            # Remove leading comma, space, dash, or any combination
            cleaned = after_prefix.lstrip(', -').strip()
            
            # Check if the cleaned result would be an exception
            # If so, don't remove the prefix (keep original)
            if cleaned:  # Only check if there's something left
                cleaned_lower = cleaned.lower()
                is_exception = False
                for exception in DESTINATION_EXCEPTIONS:
                    if cleaned_lower == exception.lower():
                        is_exception = True
                        break
                
                # Only apply the cleaning if it's not an exception
                if not is_exception:
                    result = cleaned
    
    return result.strip()

def normalize_station_name(name):
    """Normalize station name by removing commas and extra whitespace"""
    if not name:
        return ""
    # Remove commas and normalize whitespace
    normalized = name.replace(",", "").replace("  ", " ").strip()
    return normalized

def get_local_ip():
    """Get the local network IP address"""
    import socket
    try:
        # Connect to a remote address to determine the local IP
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            s.connect(('8.8.8.8', 80))
            local_ip = s.getsockname()[0]
        except Exception:
            # Fallback: try to get IP from hostname
            try:
                hostname = socket.gethostname()
                local_ip = socket.gethostbyname(hostname)
                # If it's localhost, try to get a real IP
                if local_ip.startswith('127.'):
                    # Get IP from network interfaces
                    import subprocess
                    result = subprocess.run(['hostname', '-I'], capture_output=True, text=True, timeout=2)
                    if result.returncode == 0:
                        ips = result.stdout.strip().split()
                        if ips:
                            local_ip = ips[0]
            except Exception:
                local_ip = '127.0.0.1'
        finally:
            s.close()
        return local_ip
    except Exception:
        return '127.0.0.1'

def _read_first_ipv4_for_interface(interface_name: str):
    """Best-effort: return first IPv4 address for interface (no sudo)."""
    try:
        result = subprocess.run(
            ['ip', '-4', 'addr', 'show', interface_name],
            capture_output=True,
            text=True,
            timeout=2
        )
        if result.returncode != 0:
            return ""
        # Example: "inet 192.168.4.1/24 brd ..."
        m = re.search(r'\binet\s+(\d{1,3}(?:\.\d{1,3}){3})/', result.stdout)
        return m.group(1) if m else ""
    except Exception:
        return ""

def is_access_point_mode_active():
    """Detect if the device is currently operating as an access point.

    We keep this intentionally lightweight/robust:
    - If we're clearly connected to normal WiFi (SSID present, non-AP subnet IP), we're NOT in AP mode.
    - If wlan0 has the typical AP subnet IP, we're in AP mode.
    - If a hostapd process is running, we're in AP mode.
    - If a force-AP flag exists (used by wifi-monitor), treat as AP unless WiFi is connected.
    """
    # If we have a normal WiFi connection, prefer that over any stray AP signals.
    try:
        wifi_status = get_wifi_status()
        if wifi_status.get("connected") and wifi_status.get("ssid"):
            ip = (wifi_status.get("ip") or "").strip()
            # If wlan0 has the AP subnet IP, that's still AP mode.
            if ip and not ip.startswith("192.168.4."):
                return False
    except Exception:
        # If WiFi status can't be read, continue with AP heuristics.
        pass

    try:
        # Used by wifi-monitor.py to force AP mode on boot
        if os.path.exists("/var/lib/ovbuddy-force-ap"):
            return True
    except Exception:
        pass

    # Fallback heuristic: typical AP IP on wlan0
    wlan0_ip = _read_first_ipv4_for_interface('wlan0')
    if wlan0_ip.startswith("192.168.4."):
        return True

    # wifi-monitor starts hostapd/dnsmasq as direct processes (not systemd services),
    # so check for the process name.
    try:
        result = subprocess.run(
            ['pgrep', '-x', 'hostapd'],
            capture_output=True,
            text=True,
            timeout=2
        )
        if result.returncode == 0 and result.stdout.strip():
            return True
    except Exception:
        pass

    return False

def get_access_point_ui_info():
    """AP SSID/password info as configured via config.json (for display only)."""
    ssid = AP_SSID or "OVBuddy"
    password = AP_PASSWORD if AP_PASSWORD else ""
    display_password = bool(DISPLAY_AP_PASSWORD)
    return {
        "ssid": ssid,
        "password": password,
        "display_password": display_password,
        # Typical AP address; if the user customized it, we still try to show wlan0 IP.
        "ip": _read_first_ipv4_for_interface('wlan0') or "192.168.4.1"
    }

def render_qr_code(epd=None, test_mode=False):
    """Render QR code with web server URL and instructions"""
    if not QRCODE_AVAILABLE:
        if test_mode:
            print("QR code not available (pyqrcode not installed)")
        return
    
    if not test_mode and epd is None:
        return  # Can't render without display
    
    ap_active = is_access_point_mode_active()
    ap_info = get_access_point_ui_info() if ap_active else None

    # Use AP IP when in AP mode; otherwise use Bonjour hostname.
    # (In AP mode, mDNS can be unreliable/unsupported on some clients.)
    url = f"http://{ap_info['ip']}:8080" if ap_active else "http://ovbuddy.local:8080"
    
    if test_mode:
        print(f"\nQR Code URL: {url}")
        if ap_active:
            print("[Access Point Mode]")
            print(f"SSID: {ap_info['ssid']}")
            if ap_info["password"]:
                if ap_info["display_password"]:
                    print(f"Password: {ap_info['password']}")
                else:
                    print("Password: ********")
        print("Instructions: Scan QR code to access web interface")
        print("(QR code would be displayed on the right, instructions on the left)")
        return
    
    try:
        # Generate QR code - use smaller version to fit on right side
        qr = pyqrcode.create(url, error='L', version=2)
        
        # Get QR code as PNG bytes with appropriate scale
        qr_bytes = io.BytesIO()
        # Scale 3 should give us about 105x105 pixels for version 2 QR code
        qr.png(qr_bytes, scale=3, module_color=[0, 0, 0, 255], background=[255, 255, 255, 255])
        qr_bytes.seek(0)
        
        # Load QR code image
        qr_image = Image.open(qr_bytes).convert('1')
        
        # Get display dimensions
        bg_color = 0 if INVERTED else 255
        fg_color = 255 if INVERTED else 0
        
        # Create display image
        image = Image.new('1', (DISPLAY_WIDTH, DISPLAY_HEIGHT), bg_color)
        draw = ImageDraw.Draw(image)
        
        # Split display: left side for instructions, right side for QR code
        # Reserve more space for text (about 155 pixels), rest for QR code
        text_area_width = 155
        qr_area_width = DISPLAY_WIDTH - text_area_width - 5  # 5px gap
        
        # Resize QR code to fit in right area
        qr_width, qr_height = qr_image.size
        max_qr_size = min(qr_area_width, DISPLAY_HEIGHT - 10)  # Leave some margin
        
        if qr_width > max_qr_size or qr_height > max_qr_size:
            # Scale down QR code to fit
            scale_factor = max_qr_size / max(qr_width, qr_height)
            new_width = int(qr_width * scale_factor)
            new_height = int(qr_height * scale_factor)
            qr_image = qr_image.resize((new_width, new_height), Image.Resampling.LANCZOS)
            qr_width, qr_height = new_width, new_height
        
        # Position QR code on the right side (centered vertically)
        qr_x = text_area_width + 5  # Start after text area + gap
        qr_y = (DISPLAY_HEIGHT - qr_height) // 2
        
        # Paste QR code onto display
        if INVERTED:
            # Invert QR code for inverted display
            qr_image = Image.eval(qr_image, lambda x: 255 - x)
        image.paste(qr_image, (qr_x, qr_y))
        
        # Draw instructions on the left side
        try:
            font = ImageFont.load_default()
            
            # Get WiFi status (or AP info)
            ssid = ""
            ip = get_local_ip()

            if ap_active and ap_info:
                ssid = safe_ascii(ap_info["ssid"])
                ip = ap_info["ip"] or "192.168.4.1"
            else:
                wifi_status = get_wifi_status()
                if wifi_status.get("connected") and wifi_status.get("ssid"):
                    ssid = safe_ascii(wifi_status["ssid"])
                    # Truncate SSID if too long
                    if len(ssid) > 20:
                        ssid = ssid[:17] + "..."
                    # Use IP from WiFi status if available, otherwise fallback to get_local_ip()
                    if wifi_status.get("ip"):
                        ip = wifi_status["ip"]
            
            # Instruction text lines
            instructions = [
                "Scan QR code to",
                "access web config"
            ]
            
            # Calculate starting Y position to center text vertically
            line_height = 12
            total_text_height = len(instructions) * line_height
            # Add space for SSID and IP (empty line before SSID, SSID, empty line, IP = 4 lines)
            info_spacing = 6  # Space between sections
            info_height = line_height * 4  # Empty line, SSID, empty line, and IP (4 lines)
            total_height_with_info = total_text_height + info_spacing + info_height
            start_y = (DISPLAY_HEIGHT - total_height_with_info) // 2
            
            # Draw each line of instructions
            x = 5  # Left margin
            for i, line in enumerate(instructions):
                y = start_y + (i * line_height)
                draw.text((x, y), line, font=font, fill=fg_color)
            
            # Add SSID and IP address below instructions (with empty line before SSID)
            info_y = start_y + total_text_height + info_spacing + line_height  # Add line_height for empty line before SSID
            
            # Draw SSID
            if ssid:
                ssid_text = f"{'AP' if ap_active else 'WiFi'}: {ssid}"
            else:
                ssid_text = "WiFi: Not connected"
            
            # Truncate SSID text if too long
            try:
                bbox = draw.textbbox((0, 0), ssid_text, font=font)
                text_width = bbox[2] - bbox[0]
            except:
                text_width = len(ssid_text) * 6
            
            if text_width > text_area_width - 10:
                # Truncate SSID text
                max_chars = (text_area_width - 10) // 6
                if len(ssid_text) > max_chars:
                    ssid_text = ssid_text[:max_chars-3] + "..."
            
            draw.text((x, info_y), ssid_text, font=font, fill=fg_color)
            
            # Optional: show AP password on QR screen (only in AP mode)
            if ap_active and ap_info and ap_info.get("password"):
                pwd_value = ap_info["password"] if ap_info.get("display_password") else "********"
                pwd_text = f"PWD: {safe_ascii(pwd_value)}"
                # Truncate if too long for the text area
                try:
                    bbox = draw.textbbox((0, 0), pwd_text, font=font)
                    pwd_width = bbox[2] - bbox[0]
                except Exception:
                    pwd_width = len(pwd_text) * 6
                if pwd_width > text_area_width - 10:
                    max_chars = (text_area_width - 10) // 6
                    if max_chars > 3 and len(pwd_text) > max_chars:
                        pwd_text = pwd_text[:max_chars-3] + "..."
                draw.text((x, info_y + line_height), pwd_text, font=font, fill=fg_color)

            # Draw IP address (with empty line between SSID and IP)
            # Measure "WiFi:" label width to align IP value with SSID value
            try:
                wifi_label_bbox = draw.textbbox((0, 0), "WiFi: ", font=font)
                wifi_label_width = wifi_label_bbox[2] - wifi_label_bbox[0]
            except:
                wifi_label_width = len("WiFi: ") * 6
            
            # If we printed password, push IP down one more line.
            ip_y = info_y + line_height * (3 if (ap_active and ap_info and ap_info.get("password")) else 2)
            
            # Draw IP label and value, aligning value with SSID value
            ip_label = "IP:"
            try:
                ip_label_bbox = draw.textbbox((0, 0), ip_label, font=font)
                ip_label_width = ip_label_bbox[2] - ip_label_bbox[0]
            except:
                ip_label_width = len(ip_label) * 6
            
            # Position IP label, then align IP value with SSID value
            draw.text((x, ip_y), ip_label, font=font, fill=fg_color)
            ip_value_x = x + wifi_label_width  # Align with SSID value position
            
            # Try to fit IP with port on one line
            ip_text = f"{ip}:8080"
            try:
                bbox = draw.textbbox((0, 0), ip_text, font=font)
                text_width = bbox[2] - bbox[0]
            except:
                text_width = len(ip_text) * 6
            
            if text_width <= text_area_width - 10 - (ip_value_x - x):
                draw.text((ip_value_x, ip_y), ip_text, font=font, fill=fg_color)
            else:
                # Split IP if too long (try to keep port on same line as last part)
                parts = ip.split('.')
                if len(parts) == 4:
                    # Try to fit first two parts on first line
                    first_line = '.'.join(parts[:2])
                    second_line = '.'.join(parts[2:]) + ':8080'
                    draw.text((ip_value_x, ip_y), first_line, font=font, fill=fg_color)
                    draw.text((ip_value_x, ip_y + line_height), second_line, font=font, fill=fg_color)
                else:
                    # Fallback: just show IP:port and let it wrap if needed
                    draw.text((ip_value_x, ip_y), ip_text, font=font, fill=fg_color)
            
            # Draw URL below the QR code (centered)
            url_y = qr_y + qr_height + 5  # 5px below QR code
            if url_y + line_height < DISPLAY_HEIGHT:
                # Center the URL text below the QR code
                url_display = url  # Full URL with http://
                try:
                    bbox = draw.textbbox((0, 0), url_display, font=font)
                    url_width = bbox[2] - bbox[0]
                except:
                    url_width = len(url_display) * 6
                
                # Center under QR code
                url_x = qr_x + (qr_width - url_width) // 2
                # Make sure it doesn't go off screen
                if url_x < 0:
                    url_x = qr_x
                if url_x + url_width > DISPLAY_WIDTH:
                    url_x = DISPLAY_WIDTH - url_width - 2
                
                draw.text((url_x, url_y), url_display, font=font, fill=fg_color)
            
            # Draw version number in bottom-right corner
            version_text = f"v{VERSION}"
            try:
                bbox = draw.textbbox((0, 0), version_text, font=font)
                version_width = bbox[2] - bbox[0]
                version_height = bbox[3] - bbox[1]
            except:
                version_width = len(version_text) * 6
                version_height = 8
            
            # Position in bottom-right corner with small margin
            version_x = DISPLAY_WIDTH - version_width - 3
            version_y = DISPLAY_HEIGHT - version_height - 3
            draw.text((version_x, version_y), version_text, font=font, fill=fg_color)
            
        except Exception as e:
            print(f"Error drawing instructions: {e}")
            import traceback
            traceback.print_exc()
        
        # Rotate if needed
        if FLIP_DISPLAY:
            image = image.rotate(180, expand=False)
        
        # Display
        image_buffer = epd.getbuffer(image)
        epd.display(image_buffer)
        print(f"QR code displayed: {url}")
        
    except Exception as e:
        print(f"Error rendering QR code: {e}")

def render_loading_screen(epd=None, test_mode=False):
    """Render loading screen on the e-ink display during startup"""
    if test_mode or epd is None:
        print("\n[Loading] OVBuddy Starting...")
        return
    
    try:
        bg_color = 0 if INVERTED else 255
        fg_color = 255 if INVERTED else 0
        
        # Create display image
        image = Image.new('1', (DISPLAY_WIDTH, DISPLAY_HEIGHT), bg_color)
        draw = ImageDraw.Draw(image)
        
        # Load font
        font = ImageFont.load_default()
        line_height = 12
        
        # Center the text vertically
        text_lines = [
            "Starting..."
            " ",
        ]
        total_text_height = len(text_lines) * line_height
        start_y = (DISPLAY_HEIGHT - total_text_height) // 2
        
        # Draw each line centered horizontally
        for i, line in enumerate(text_lines):
            # Get text width for centering
            bbox = draw.textbbox((0, 0), line, font=font)
            text_width = bbox[2] - bbox[0]
            x = (DISPLAY_WIDTH - text_width) // 2
            y = start_y + (i * line_height)
            draw.text((x, y), line, font=font, fill=fg_color)
        
        # Rotate if needed
        if FLIP_DISPLAY:
            image = image.rotate(180, expand=False)
        
        # Display
        image_buffer = epd.getbuffer(image)
        epd.display(image_buffer)
        
    except Exception as e:
        print(f"Error rendering loading screen: {e}")

def render_ap_info(ssid, password=None, display_password=False, epd=None, test_mode=False):
    """Render Access Point information on the e-ink display
    
    Args:
        ssid: The AP SSID to display
        password: The AP password (optional)
        display_password: Whether to show the password on screen
        epd: The e-ink display object
        test_mode: If True, print to console instead of displaying
    """
    if test_mode or epd is None:
        print("\n[Access Point Mode]")
        print(f"SSID: {ssid}")
        if display_password and password:
            print(f"Password: {password}")
        elif password:
            print("Password: ********")
        else:
            print("Password: (none - open network)")
        print("IP: 192.168.4.1:8080")
        return
    
    try:
        bg_color = 0 if INVERTED else 255
        fg_color = 255 if INVERTED else 0
        
        # Create display image
        image = Image.new('1', (DISPLAY_WIDTH, DISPLAY_HEIGHT), bg_color)
        draw = ImageDraw.Draw(image)
        
        # Load fonts
        font = ImageFont.load_default()
        try:
            font_bold = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 11)
        except:
            font_bold = font
        
        line_height = 14
        y = 5
        
        # Title
        title = "Access Point Mode"
        try:
            bbox = draw.textbbox((0, 0), title, font=font_bold)
            title_width = bbox[2] - bbox[0]
        except:
            title_width = len(title) * 7
        
        title_x = (DISPLAY_WIDTH - title_width) // 2
        draw.text((title_x, y), title, font=font_bold, fill=fg_color)
        y += line_height + 8
        
        # Separator line
        draw.line([(5, y), (DISPLAY_WIDTH - 5, y)], fill=fg_color, width=1)
        y += 8
        
        # WiFi Network (SSID)
        draw.text((5, y), "WiFi Network:", font=font_bold, fill=fg_color)
        y += line_height
        
        # SSID (may need to wrap if too long)
        ssid_text = ssid
        max_width = DISPLAY_WIDTH - 15
        try:
            bbox = draw.textbbox((0, 0), ssid_text, font=font)
            text_width = bbox[2] - bbox[0]
        except:
            text_width = len(ssid_text) * 6
        
        if text_width > max_width:
            # Truncate with ellipsis
            max_chars = max_width // 6
            ssid_text = ssid_text[:max_chars-3] + "..."
        
        draw.text((10, y), ssid_text, font=font, fill=fg_color)
        y += line_height + 4
        
        # Password
        if password:
            draw.text((5, y), "Password:", font=font_bold, fill=fg_color)
            y += line_height
            
            if display_password:
                # Show actual password (may need to wrap)
                pwd_text = password
                try:
                    bbox = draw.textbbox((0, 0), pwd_text, font=font)
                    text_width = bbox[2] - bbox[0]
                except:
                    text_width = len(pwd_text) * 6
                
                if text_width > max_width:
                    # Split into multiple lines if needed
                    chars_per_line = max_width // 6
                    for i in range(0, len(pwd_text), chars_per_line):
                        line_text = pwd_text[i:i+chars_per_line]
                        draw.text((10, y), line_text, font=font, fill=fg_color)
                        y += line_height
                else:
                    draw.text((10, y), pwd_text, font=font, fill=fg_color)
                    y += line_height
            else:
                # Show asterisks
                draw.text((10, y), "********", font=font, fill=fg_color)
                y += line_height
        else:
            draw.text((5, y), "Password:", font=font_bold, fill=fg_color)
            y += line_height
            draw.text((10, y), "(open network)", font=font, fill=fg_color)
            y += line_height
        
        y += 4
        
        # Web Interface
        draw.text((5, y), "Web Interface:", font=font_bold, fill=fg_color)
        y += line_height
        draw.text((10, y), "http://192.168.4.1:8080", font=font, fill=fg_color)
        y += line_height + 4
        
        # Instructions
        draw.text((5, y), "Connect to this network", font=font, fill=fg_color)
        y += line_height
        draw.text((5, y), "to configure WiFi", font=font, fill=fg_color)
        
        # Rotate if needed
        if FLIP_DISPLAY:
            image = image.rotate(180, expand=False)
        
        # Display
        image_buffer = epd.getbuffer(image)
        epd.display(image_buffer)
        
        print(f"Displayed AP info: SSID={ssid}, Password={'shown' if display_password and password else 'hidden'}")
        
    except Exception as e:
        print(f"Error rendering AP info: {e}")
        import traceback
        traceback.print_exc()

def render_update_screen(epd=None, status="Updating...", version=None, test_mode=False):
    """Render update progress screen on the e-ink display"""
    if test_mode or epd is None:
        if version:
            print(f"\n[{status}] Updating to v{version}...")
        else:
            print(f"\n[{status}]")
        return
    
    try:
        bg_color = 0 if INVERTED else 255
        fg_color = 255 if INVERTED else 0
        
        # Create display image
        image = Image.new('1', (DISPLAY_WIDTH, DISPLAY_HEIGHT), bg_color)
        draw = ImageDraw.Draw(image)
        
        # Load font
        font = ImageFont.load_default()
        line_height = 12
        
        # Title
        title = "Updating..."
        title_y = 10
        draw.text((5, title_y), title, font=font, fill=fg_color)
        
        # Version info
        version_y = title_y + line_height + 5
        if version:
            version_text = f"v{VERSION} -> v{version}"
            draw.text((5, version_y), version_text, font=font, fill=fg_color)
            status_y = version_y + line_height + 10
        else:
            status_y = title_y + line_height + 10
        # Wrap status if too long
        max_chars = (DISPLAY_WIDTH - 10) // 6
        if len(status) > max_chars:
            # Split into multiple lines
            words = status.split()
            lines = []
            current_line = ""
            for word in words:
                if len(current_line + " " + word) <= max_chars:
                    current_line += (" " if current_line else "") + word
                else:
                    if current_line:
                        lines.append(current_line)
                    current_line = word
            if current_line:
                lines.append(current_line)
            status_lines = lines[:3]  # Max 3 lines
        else:
            status_lines = [status]
        
        for i, line in enumerate(status_lines):
            draw.text((5, status_y + i * line_height), line, font=font, fill=fg_color)
        
        # Rotate if needed
        if FLIP_DISPLAY:
            image = image.rotate(180, expand=False)
        
        # Display
        image_buffer = epd.getbuffer(image)
        epd.display(image_buffer)
        
    except Exception as e:
        print(f"Error rendering update screen: {e}")

def format_configuration():
    """Format current configuration as a displayable message"""
    lines = []
    
    # Get WiFi status and show SSID
    wifi_status = get_wifi_status()
    if wifi_status.get("connected") and wifi_status.get("ssid"):
        ssid = safe_ascii(wifi_status["ssid"])
        # Truncate SSID if too long
        if len(ssid) > 20:
            ssid = ssid[:17] + "..."
        lines.append(f"WiFi: {ssid}")
        # Show IP if available
        if wifi_status.get("ip"):
            lines.append(f"IP: {wifi_status['ip']}")
    else:
        lines.append("WiFi: Not connected")
    
    lines.append("")  # Empty line for spacing
    
    # Format stations
    if isinstance(STATIONS, list):
        stations_str = ", ".join([safe_ascii(s) for s in STATIONS[:2]])  # Show first 2
        if len(STATIONS) > 2:
            stations_str += f" (+{len(STATIONS)-2})"
    else:
        stations_str = safe_ascii(STATIONS)
    lines.append(f"Stations: {stations_str}")
    
    # Format lines
    lines_str = ", ".join(LINES[:4])  # Show first 4
    if len(LINES) > 4:
        lines_str += f" (+{len(LINES)-4})"
    lines.append(f"Lines: {lines_str}")
    
    # Refresh interval
    lines.append(f"Refresh: {REFRESH_INTERVAL}s")
    
    # Display settings
    display_settings = []
    if FLIP_DISPLAY:
        display_settings.append("Flip")
    if INVERTED:
        display_settings.append("Inverted")
    if USE_PARTIAL_REFRESH:
        display_settings.append("Partial")
    if display_settings:
        lines.append(f"Display: {', '.join(display_settings)}")
    else:
        lines.append("Display: Normal")
    
    # Max departures
    lines.append(f"Max: {MAX_DEPARTURES} connections")
    
    return "\n".join(lines)

def render_board(departures, epd=None, error_msg=None, is_first_successful=False, last_was_successful=False, test_mode=False):
    """Draw the departures on the eInk display (or print in test mode)"""
    
    # Header - show station name(s)
    if test_mode:
        # In test mode, always show "Zürich Saalsporthalle"
        header_text = safe_ascii("Zürich Saalsporthalle")
    elif isinstance(STATIONS, list) and len(STATIONS) > 1:
        # Check if stations differ only by comma/whitespace
        normalized_stations = [normalize_station_name(s) for s in STATIONS]
        # Check if all normalized stations are the same
        if len(set(normalized_stations)) == 1:
            # All stations are essentially the same, show the normalized name
            header_text = safe_ascii(normalized_stations[0])
        else:
            # Different stations, show count
            header_text = f"{len(STATIONS)} stations"
    else:
        station_name = STATIONS[0] if isinstance(STATIONS, list) else STATIONS
        header_text = safe_ascii(station_name)
    
    # Truncate header if too long
    if len(header_text) > 30:
        header_text = header_text[:27] + "..."
    
    if TEST_MODE:
        # Test mode: just print to console
        print("\n" + "=" * 40)
        print(header_text)
        print("-" * 40)
        
        if error_msg:
            # Check if this is a configuration message (has newlines)
            if "\n" in error_msg:
                print("Configuration:")
                print(error_msg)
            else:
                print(f"Error: {error_msg}")
        elif departures:
            for entry in departures[:MAX_DEPARTURES]:
                line_num = format_line_number(entry)
                dest_raw = entry["to"]
                dest = safe_ascii(clean_destination_name(dest_raw))  # Clean and convert to ASCII
                time_str = entry["stop"]["departure"][11:16]
                delay_seconds = entry.get("stop", {}).get("delay", 0)
                delay_str = ""
                if delay_seconds and delay_seconds >= 60:  # Only show if >= 1 minute
                    delay_minutes = delay_seconds // 60
                    # Use ANSI bold escape codes for terminal output
                    delay_str = f" \033[1m>{delay_minutes}min\033[0m"  # Bold in terminal
                print(f"{line_num} {dest} {time_str}{delay_str}")
        else:
            print("No departures available")
        print("=" * 40 + "\n")
        return
    
    # Real mode: render to display
    # Set background and foreground colors based on inverted flag
    bg_color = 0 if INVERTED else 255  # Black if inverted, white if normal
    fg_color = 255 if INVERTED else 0  # White if inverted, black if normal
    
    # Create a fresh image each time (don't reuse)
    image = Image.new('1', (DISPLAY_WIDTH, DISPLAY_HEIGHT), bg_color)
    draw = ImageDraw.Draw(image)
    
    # Ensure we're drawing on a fresh canvas by explicitly filling background
    draw.rectangle([(0, 0), (DISPLAY_WIDTH, DISPLAY_HEIGHT)], fill=bg_color)
    
    # Calculate font size based on number of departures to show
    # More space per line = larger font
    available_height = DISPLAY_HEIGHT - 12  # Subtract header space
    line_spacing = 3  # Minimum spacing between lines
    # Use actual number of departures (up to MAX_DEPARTURES) for font calculation
    num_departures_to_show = min(len(departures) if departures else 0, MAX_DEPARTURES)
    if num_departures_to_show == 0:
        num_departures_to_show = MAX_DEPARTURES  # Fallback to MAX_DEPARTURES for font sizing
    line_height = (available_height - line_spacing * (num_departures_to_show - 1)) // num_departures_to_show
    
    # Try to load a larger font if available, otherwise use default
    # Default font is ~8px tall, we'll try to scale up if we have space
    font_header = ImageFont.load_default()
    
    # For line font, try to use a larger size if we have space
    try:
        # Try common system fonts
        font_paths = [
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
            "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
            "/usr/share/fonts/truetype/freefont/FreeSans.ttf",
        ]
        font_bold_paths = [
            "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
            "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
            "/usr/share/fonts/truetype/freefont/FreeSansBold.ttf",
        ]
        font_size = min(line_height - 2, 16)  # Cap at 16px, leave 2px margin
        font_line = None
        font_line_bold = None
        for font_path in font_paths:
            if os.path.exists(font_path):
                font_line = ImageFont.truetype(font_path, font_size)
                if test_mode:
                    print(f"Loaded regular font: {font_path}")
                break
        for font_path in font_bold_paths:
            if os.path.exists(font_path):
                font_line_bold = ImageFont.truetype(font_path, font_size)
                if test_mode:
                    print(f"Loaded bold font: {font_path}")
                break
        if font_line is None:
            # Fallback to default font
            font_line = ImageFont.load_default()
            if test_mode:
                print("Using default font (no TrueType fonts found)")
        if font_line_bold is None:
            # Fallback to regular font if bold not available
            font_line_bold = font_line
            if test_mode:
                print("Bold font not available, using regular font for delays")
    except Exception:
        # If font loading fails, use default
        font_line = ImageFont.load_default()
        font_line_bold = font_line
    
    # Draw header
    draw.text((0, 0), header_text, font=font_header, fill=fg_color)
    
    # Always show update time in top right corner
    current_time = time.strftime("%H:%M")
    # Get actual text width using textbbox (more accurate)
    try:
        bbox = draw.textbbox((0, 0), current_time, font=font_header)
        time_width = bbox[2] - bbox[0]
    except:
        # Fallback: approximate width (default font ~6px per char)
        time_width = len(current_time) * 6
    time_x = DISPLAY_WIDTH - time_width - 2  # 2px margin from right edge
    draw.text((time_x, 0), current_time, font=font_header, fill=fg_color)
    
    draw.line((0, 10, DISPLAY_WIDTH, 10), fill=fg_color)

    # Draw content
    y = 12
    if error_msg:
        # Show error message (or configuration on first refresh)
        # Check if this looks like a configuration (has newlines)
        error_text = safe_ascii(error_msg)
        if "\n" in error_text:
            # Multi-line message (configuration), render line by line
            lines = error_text.split("\n")
            for line in lines:
                if line.strip():
                    draw.text((0, y), line.strip(), font=font_line, fill=fg_color)
                    y += 15
                    if y >= DISPLAY_HEIGHT - 5:
                        break
        else:
            # Single-line error message, wrap if needed
            draw.text((0, y), "Error:", font=font_line, fill=fg_color)
            y += 15
            # Split long error messages into multiple lines
            words = error_text.split()
            line = ""
            for word in words:
                test_line = line + word + " " if line else word + " "
                if len(test_line) > 30:  # Approximate chars per line
                    if line:
                        draw.text((0, y), line.strip(), font=font_line, fill=fg_color)
                        y += 15
                        if y >= DISPLAY_HEIGHT - 5:
                            break
                    line = word + " "
                else:
                    line = test_line
            if line and y < DISPLAY_HEIGHT - 5:
                draw.text((0, y), line.strip(), font=font_line, fill=fg_color)
    elif departures:
        # Clear the departure area first
        departure_area_top = y
        departure_area_bottom = DISPLAY_HEIGHT - 5
        draw.rectangle([(0, departure_area_top), (DISPLAY_WIDTH, departure_area_bottom)], fill=bg_color)
        
        # Calculate dynamic line spacing based on available space
        num_to_show = min(len(departures), MAX_DEPARTURES)
        available_space = DISPLAY_HEIGHT - y - 5  # Leave 5px bottom margin
        if num_to_show > 0:
            line_spacing = max(available_space // num_to_show, 15)  # Minimum 15px spacing
        else:
            line_spacing = 20  # Default spacing
        
        # Fixed positions for alignment
        # Estimate character width (monospaced font ~6-7px per char)
        char_width = 7  # Conservative estimate
        line_num_x = 0
        dest_x = 4 * char_width  # After 3-character line number + 1 char space
        # Right edge for time/delay (will be calculated per line based on actual delay)
        time_x = DISPLAY_WIDTH - 5  # 5px margin from right edge
        
        for entry in departures[:MAX_DEPARTURES]:
            line_num = format_line_number(entry)  # Always 3 chars, aligned
            dest_raw = entry["to"]
            dest = safe_ascii(clean_destination_name(dest_raw))  # Clean and convert to ASCII
            time_str = entry["stop"]["departure"][11:16]  # HH:MM
            
            # Check for delay (in seconds)
            # Only show delays that are meaningful (>= 1 minute)
            delay_seconds = entry.get("stop", {}).get("delay", 0)
            delay_str = ""
            if delay_seconds and delay_seconds >= 60:  # Only show if >= 1 minute
                delay_minutes = delay_seconds // 60
                delay_str = f">{delay_minutes}min"  # Using > symbol
            
            # Get actual width needed for time (always present)
            try:
                bbox = draw.textbbox((0, 0), time_str, font=font_line)
                time_width = bbox[2] - bbox[0]
            except:
                time_width = 5 * char_width  # HH:MM is 5 chars
            
            # Get actual width needed for delay (if present)
            delay_width = 0
            if delay_str:
                try:
                    bbox = draw.textbbox((0, 0), f" {delay_str}", font=font_line_bold)
                    delay_width = bbox[2] - bbox[0]
                except:
                    delay_width = (1 + len(delay_str)) * char_width  # space + delay text
            
            time_delay_width = time_width + delay_width
            
            # Calculate max width for destination (between line number and time/delay)
            dest_max_width = time_x - dest_x - time_delay_width - 5  # 5px margin
            dest_max_chars = max(1, int(dest_max_width / char_width) - 2)  # Leave margin
            
            # Truncate destination if needed
            if len(dest) > dest_max_chars:
                truncate_to = max(1, dest_max_chars - 3)  # Leave room for "..."
                dest = dest[:truncate_to] + "..."
            
            # Draw components separately for perfect alignment
            # 1. Line number (always at x=0, 3 chars wide)
            draw.text((line_num_x, y), line_num, font=font_line, fill=fg_color)
            
            # 2. Destination (after line number with space, no arrow)
            draw.text((dest_x, y), dest, font=font_line, fill=fg_color)
            
            # 3. Time (right-aligned at fixed position)
            time_draw_x = time_x - time_delay_width  # Right-align using calculated width
            draw.text((time_draw_x, y), time_str, font=font_line, fill=fg_color)
            
            # 4. Delay in bold (if present, immediately after time)
            if delay_str:
                delay_draw_x = time_draw_x + time_width
                draw.text((delay_draw_x, y), f" {delay_str}", font=font_line_bold, fill=fg_color)
            
            y += line_spacing  # Dynamic spacing based on available space
    else:
        # No departures found
        draw.text((0, y), "No departures", font=font_line, fill=fg_color)
        y += 15
        draw.text((0, y), "available", font=font_line, fill=fg_color)

    # Send to display
    # Note: We don't call epd.sleep() here because it closes the SPI connection
    # The display will stay awake between updates
    try:
        # Rotate image 180 degrees if FLIP_DISPLAY is enabled
        if FLIP_DISPLAY:
            image = image.rotate(180, expand=False)
        
        # Get the image buffer
        image_buffer = epd.getbuffer(image)
        
        # Debug: log what we're displaying
        current_time = time.strftime("%H:%M:%S")
        if departures:
            first_dep = departures[0]
            line_info = f"{format_line_number(first_dep)} -> {safe_ascii(first_dep['to'])}"
            print(f"[{current_time}] Updating display: {len(departures)} departures, first: {line_info}")
        else:
            print(f"[{current_time}] Updating display: {error_msg if error_msg else 'No departures'}")
        
        # Determine refresh type based on state
        # Always use full refresh for:
        # - Error messages
        # - First successful fetch
        # - Switching from error to success
        # - When partial refresh is disabled
        # Only use partial refresh when:
        # - Last fetch was successful AND current fetch is successful
        # - Partial refresh is enabled
        has_error = error_msg is not None
        switching_from_error = has_error or not last_was_successful
        
        use_partial = (USE_PARTIAL_REFRESH and 
                      not is_first_successful and 
                      not has_error and 
                      last_was_successful)
        
        if use_partial:
            # Partial refresh: updates only changed pixels, less flashing but may have ghosting
            print("Using partial refresh")
            epd.displayPartial(image_buffer)
        else:
            # Full refresh: complete refresh cycle, more reliable but more flashing
            reason = []
            if is_first_successful:
                reason.append("first successful fetch")
            if has_error:
                reason.append("error message")
            if switching_from_error and not has_error:
                reason.append("switching from error to success")
            if not USE_PARTIAL_REFRESH:
                reason.append("partial refresh disabled")
            if reason:
                print(f"Using full refresh: {', '.join(reason)}")
            epd.display(image_buffer)
        
    except OSError as e:
        # If SPI connection is closed, reinitialize the display
        print(f"SPI error, reinitializing display: {e}")
        if epd:
            try:
                epd.init()
                image_buffer = epd.getbuffer(image)
                # On reinit, always use full refresh
                epd.display(image_buffer)
            except Exception as e2:
                print(f"Failed to reinitialize display: {e2}")
                raise

# --------------------------
# WIFI MANAGEMENT
# --------------------------
import subprocess

def get_wifi_status():
    """Get current WiFi connection status"""
    try:
        # Try using wpa_cli first (most common on Raspberry Pi)
        result = subprocess.run(['wpa_cli', '-i', 'wlan0', 'status'], 
                              capture_output=True, text=True, timeout=5)
        if result.returncode == 0:
            status = {}
            for line in result.stdout.strip().split('\n'):
                if '=' in line:
                    key, value = line.split('=', 1)
                    status[key] = value
            return {
                "connected": status.get('wpa_state') == 'COMPLETED',
                "ssid": status.get('ssid', ''),
                "ip": status.get('ip_address', ''),
                "signal": status.get('signal', ''),
                "method": "wpa_cli"
            }
    except (subprocess.TimeoutExpired, FileNotFoundError, subprocess.SubprocessError):
        pass
    
    # Fallback: try iwconfig
    try:
        result = subprocess.run(['iwconfig', 'wlan0'], 
                              capture_output=True, text=True, timeout=5)
        if result.returncode == 0:
            output = result.stdout
            ssid = ''
            signal = ''
            if 'ESSID:' in output:
                ssid = output.split('ESSID:')[1].split()[0].strip('"')
            if 'Signal level=' in output:
                signal = output.split('Signal level=')[1].split()[0]
            
            # Get IP address
            ip = ''
            try:
                ip_result = subprocess.run(['hostname', '-I'], 
                                         capture_output=True, text=True, timeout=2)
                if ip_result.returncode == 0:
                    ips = ip_result.stdout.strip().split()
                    # Filter for wlan0 IP (usually first non-localhost)
                    for addr in ips:
                        if not addr.startswith('127.'):
                            ip = addr
                            break
            except:
                pass
            
            return {
                "connected": bool(ssid),
                "ssid": ssid,
                "ip": ip,
                "signal": signal,
                "method": "iwconfig"
            }
    except (subprocess.TimeoutExpired, FileNotFoundError, subprocess.SubprocessError):
        pass
    
    return {
        "connected": False,
        "ssid": "",
        "ip": "",
        "signal": "",
        "method": "unknown",
        "error": "Could not determine WiFi status"
    }

def scan_wifi_networks():
    """Scan for available WiFi networks"""
    networks = []
    
    # Try using iwlist (most reliable on Raspberry Pi)
    # First, try to find the WiFi interface name
    wifi_interface = None
    try:
        # Try common interface names
        for interface in ['wlan0', 'wlan1', 'wlp2s0', 'wlp3s0']:
            result = subprocess.run(['ip', 'link', 'show', interface], 
                                  capture_output=True, text=True, timeout=2)
            if result.returncode == 0:
                wifi_interface = interface
                break
    except Exception:
        pass
    
    # Default to wlan0 if we couldn't detect
    if not wifi_interface:
        wifi_interface = 'wlan0'
    
    try:
        result = subprocess.run(['sudo', 'iwlist', wifi_interface, 'scan'], 
                              capture_output=True, text=True, timeout=15)
        if result.returncode == 0:
            current_cell = {}
            for line in result.stdout.split('\n'):
                line = line.strip()
                if 'Cell' in line and 'Address:' in line:
                    if current_cell and 'ssid' in current_cell:
                        networks.append(current_cell)
                    current_cell = {}
                elif 'ESSID:' in line:
                    essid = line.split('ESSID:')[1].strip().strip('"')
                    if essid:  # Only add networks with names
                        current_cell['ssid'] = essid
                elif 'Encryption key:' in line:
                    current_cell['encrypted'] = 'on' in line.lower()
                elif 'Quality=' in line:
                    # Extract signal strength
                    if 'Signal level=' in line:
                        signal = line.split('Signal level=')[1].split()[0]
                        try:
                            # Convert to percentage (usually -100 to 0 dBm)
                            dbm = int(signal)
                            quality = max(0, min(100, 2 * (dbm + 100)))
                            current_cell['signal'] = quality
                        except:
                            current_cell['signal'] = signal
            
            if current_cell and 'ssid' in current_cell:
                networks.append(current_cell)
            
            # Remove duplicates and sort by signal strength
            seen = set()
            unique_networks = []
            for net in networks:
                if net.get('ssid') and net['ssid'] not in seen:
                    seen.add(net['ssid'])
                    unique_networks.append(net)
            
            # Sort by signal strength (highest first)
            unique_networks.sort(key=lambda x: x.get('signal', 0), reverse=True)
            return unique_networks
        else:
            # iwlist failed, try nmcli as fallback (doesn't require sudo)
            try:
                result_nm = subprocess.run(['nmcli', '-t', '-f', 'SSID,SIGNAL,SECURITY', 'device', 'wifi', 'list'], 
                                          capture_output=True, text=True, timeout=10)
                if result_nm.returncode == 0 and result_nm.stdout.strip():
                    networks = []
                    for line in result_nm.stdout.strip().split('\n'):
                        if line:
                            parts = line.split(':')
                            if len(parts) >= 2:
                                ssid = parts[0]
                                if ssid:  # Skip empty SSIDs
                                    network = {'ssid': ssid}
                                    if len(parts) >= 2:
                                        try:
                                            network['signal'] = int(parts[1])
                                        except:
                                            pass
                                    if len(parts) >= 3:
                                        network['encrypted'] = parts[2] != '' and 'WPA' in parts[2] or 'WEP' in parts[2]
                                    networks.append(network)
                    if networks:
                        networks.sort(key=lambda x: x.get('signal', 0), reverse=True)
                        return networks
            except (FileNotFoundError, subprocess.SubprocessError):
                pass
            
            # If nmcli also failed, provide better error message
            error_msg = result.stderr.strip() if result.stderr else result.stdout.strip() or "Unknown error"
            if "Operation not permitted" in error_msg or "Permission denied" in error_msg or "sudo" in error_msg.lower():
                return {"error": "Permission denied. Configure passwordless sudo: sudo visudo, then add: pi ALL=(ALL) NOPASSWD: /sbin/iwlist"}
            elif "No such device" in error_msg or "Device or resource busy" in error_msg:
                return {"error": f"WiFi interface {wifi_interface} not available or busy. Make sure WiFi is enabled."}
            return {"error": f"Scan failed: {error_msg}"}
    except subprocess.TimeoutExpired:
        return {"error": "Scan timed out. This may take up to 15 seconds."}
    except FileNotFoundError:
        return {"error": "iwlist command not found. Install wireless-tools: sudo apt-get install wireless-tools"}
    except subprocess.SubprocessError as e:
        return {"error": f"Scan failed: {str(e)}"}
    except Exception as e:
        return {"error": f"Unexpected error: {str(e)}"}
    
    return {"error": "Could not scan for networks. Please check WiFi interface and permissions."}

def get_service_status(service_name):
    """Get the status of a systemd service"""
    try:
        # Get service status
        result = subprocess.run(['sudo', '-n', 'systemctl', 'is-active', service_name],
                              capture_output=True, text=True, timeout=5)
        is_active = result.stdout.strip() == 'active'
        
        # Get more detailed status
        result = subprocess.run(['sudo', '-n', 'systemctl', 'status', service_name, '--no-pager'],
                              capture_output=True, text=True, timeout=5)
        status_output = result.stdout
        
        # Parse status information
        status = {
            "name": service_name,
            "active": is_active,
            "status": "running" if is_active else "stopped",
            "enabled": False,
            "uptime": "",
            "memory": "",
            "cpu": ""
        }
        
        # Check if enabled
        result = subprocess.run(['sudo', '-n', 'systemctl', 'is-enabled', service_name],
                              capture_output=True, text=True, timeout=5)
        status["enabled"] = result.stdout.strip() == 'enabled'
        
        # Parse additional info from status output
        for line in status_output.split('\n'):
            if 'Active:' in line:
                # Extract uptime/duration if available
                if 'since' in line:
                    parts = line.split('since')
                    if len(parts) > 1:
                        status["uptime"] = parts[1].strip().split(';')[0]
            elif 'Memory:' in line:
                status["memory"] = line.split('Memory:')[1].strip().split()[0] if 'Memory:' in line else ""
            elif 'CPU:' in line:
                status["cpu"] = line.split('CPU:')[1].strip().split()[0] if 'CPU:' in line else ""
        
        return status
    except subprocess.TimeoutExpired:
        return {"name": service_name, "active": False, "status": "timeout", "error": "Command timed out"}
    except Exception as e:
        return {"name": service_name, "active": False, "status": "error", "error": str(e)}

def control_service(service_name, action):
    """Control a systemd service (start, stop, restart)"""
    if action not in ['start', 'stop', 'restart']:
        return {"success": False, "error": f"Invalid action: {action}"}
    
    try:
        # Execute the systemctl command
        result = subprocess.run(['sudo', '-n', 'systemctl', action, service_name],
                              capture_output=True, text=True, timeout=10)
        
        if result.returncode == 0:
            # Wait a moment for the service to change state
            import time
            time.sleep(1)
            
            # Get updated status
            status = get_service_status(service_name)
            return {
                "success": True,
                "message": f"Service {service_name} {action}ed successfully",
                "status": status
            }
        else:
            error_msg = result.stderr.strip() if result.stderr else result.stdout.strip()
            return {"success": False, "error": error_msg or f"Failed to {action} service"}
    except subprocess.TimeoutExpired:
        return {"success": False, "error": "Command timed out"}
    except Exception as e:
        return {"success": False, "error": str(e)}

def connect_to_wifi(ssid, password=None):
    """Connect to a WiFi network using wpa_supplicant or nmcli"""
    try:
        # Check if we need sudo
        import os
        if os.geteuid() != 0:
            # Need to use sudo
            sudo_cmd = ['sudo', '-n']  # -n means non-interactive
        else:
            sudo_cmd = []
        
        # Try nmcli first (NetworkManager - more common on modern Raspberry Pi OS)
        try:
            # Check if nmcli is available
            nmcli_check = subprocess.run(['which', 'nmcli'], 
                                        capture_output=True, timeout=2)
            if nmcli_check.returncode == 0:
                # Use nmcli to connect
                if password:
                    result = subprocess.run(['nmcli', 'device', 'wifi', 'connect', ssid, 
                                           'password', password],
                                          capture_output=True, text=True, timeout=30)
                else:
                    result = subprocess.run(['nmcli', 'device', 'wifi', 'connect', ssid],
                                          capture_output=True, text=True, timeout=30)
                
                if result.returncode == 0:
                    # Persist last-known WiFi so wifi-monitor can try it on next boot
                    try:
                        global LAST_WIFI_SSID, LAST_WIFI_PASSWORD
                        LAST_WIFI_SSID = str(ssid)
                        LAST_WIFI_PASSWORD = str(password or "")
                        save_config()
                    except Exception as e:
                        print(f"Warning: could not save last WiFi details: {e}")
                    return {"success": True, "message": f"Successfully connected to {ssid}"}
                else:
                    error_msg = result.stderr.strip() if result.stderr else result.stdout.strip()
                    # If nmcli failed, fall through to try wpa_supplicant method
                    print(f"nmcli failed: {error_msg}, trying wpa_supplicant method...")
        except (FileNotFoundError, subprocess.SubprocessError) as e:
            # nmcli not available, fall through to wpa_supplicant method
            print(f"nmcli not available: {e}, trying wpa_supplicant method...")
            pass
        
        # Fall back to wpa_supplicant method
        # Use wpa_cli to add network directly (more reliable than editing config file)
        import time
        try:
            # Add network using wpa_cli
            result = subprocess.run(sudo_cmd + ['wpa_cli', '-i', 'wlan0', 'add_network'],
                                  capture_output=True, text=True, timeout=5)
            if result.returncode != 0:
                return {"success": False, "error": f"Failed to add network: {result.stderr}"}
            
            network_id = result.stdout.strip()
            if not network_id.isdigit():
                return {"success": False, "error": f"Invalid network ID returned: {network_id}"}
            
            # Set SSID
            result = subprocess.run(sudo_cmd + ['wpa_cli', '-i', 'wlan0', 'set_network', network_id, 'ssid', f'"{ssid}"'],
                                  capture_output=True, text=True, timeout=5)
            if result.returncode != 0 or 'FAIL' in result.stdout:
                return {"success": False, "error": f"Failed to set SSID: {result.stdout}"}
            
            # Set password or key_mgmt
            if password:
                result = subprocess.run(sudo_cmd + ['wpa_cli', '-i', 'wlan0', 'set_network', network_id, 'psk', f'"{password}"'],
                                      capture_output=True, text=True, timeout=5)
                if result.returncode != 0 or 'FAIL' in result.stdout:
                    return {"success": False, "error": f"Failed to set password: {result.stdout}"}
            else:
                result = subprocess.run(sudo_cmd + ['wpa_cli', '-i', 'wlan0', 'set_network', network_id, 'key_mgmt', 'NONE'],
                                      capture_output=True, text=True, timeout=5)
                if result.returncode != 0 or 'FAIL' in result.stdout:
                    return {"success": False, "error": f"Failed to set key_mgmt: {result.stdout}"}
            
            # Set priority to make it preferred
            subprocess.run(sudo_cmd + ['wpa_cli', '-i', 'wlan0', 'set_network', network_id, 'priority', '10'],
                          capture_output=True, timeout=5)
            
            # Enable the network
            result = subprocess.run(sudo_cmd + ['wpa_cli', '-i', 'wlan0', 'enable_network', network_id],
                                  capture_output=True, text=True, timeout=5)
            if result.returncode != 0 or 'FAIL' in result.stdout:
                return {"success": False, "error": f"Failed to enable network: {result.stdout}"}
            
            # Save configuration
            subprocess.run(sudo_cmd + ['wpa_cli', '-i', 'wlan0', 'save_config'],
                          capture_output=True, timeout=5)
            
            # Disconnect from current network
            subprocess.run(sudo_cmd + ['wpa_cli', '-i', 'wlan0', 'disconnect'],
                          capture_output=True, timeout=5)
            time.sleep(0.5)
            
            # Select the new network
            result = subprocess.run(sudo_cmd + ['wpa_cli', '-i', 'wlan0', 'select_network', network_id],
                                  capture_output=True, text=True, timeout=5)
            if result.returncode != 0 or 'FAIL' in result.stdout:
                return {"success": False, "error": f"Failed to select network: {result.stdout}"}
            
            # Reconnect
            subprocess.run(sudo_cmd + ['wpa_cli', '-i', 'wlan0', 'reconnect'],
                          capture_output=True, timeout=5)
            
            # Wait a moment for connection
            time.sleep(2)
            
            # Trigger DHCP to get new IP
            subprocess.run(sudo_cmd + ['dhclient', '-r', 'wlan0'],
                          capture_output=True, timeout=5)
            subprocess.run(sudo_cmd + ['dhclient', 'wlan0'],
                          capture_output=True, timeout=10)
            
        except Exception as e:
            return {"success": False, "error": f"Connection failed: {str(e)}"}
        
        return {"success": True, "message": f"Network {ssid} configured. Connecting..."}
    
    except Exception as e:
        return {"success": False, "error": f"Connection failed: {str(e)}"}

# --------------------------
# WEB SERVER
# --------------------------
if FLASK_AVAILABLE:
    import os
    # Get the directory where this script is located
    script_dir = os.path.dirname(os.path.abspath(__file__))
    app = Flask(__name__, 
                template_folder=os.path.join(script_dir, 'templates'),
                static_folder=os.path.join(script_dir, 'static'))
else:
    app = None
zeroconf = None
service_info = None

if FLASK_AVAILABLE:
    @app.route('/test')
    def test():
        """Simple test endpoint to verify Flask is working"""
        return "<h1>Flask is working!</h1><p>If you see this, Flask is responding correctly.</p>"
    
    @app.route('/')
    def index():
        """Serve the web configuration interface"""
        try:
            print("Rendering index.html template...")
            template_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'templates', 'index.html')
            print(f"Template path: {template_path}")
            print(f"Template exists: {os.path.exists(template_path)}")
            if not os.path.exists(template_path):
                return f"Template not found at: {template_path}", 404
            result = render_template('index.html')
            print(f"Template rendered successfully, length: {len(result) if result else 0}")
            if not result or len(result) == 0:
                return "Template rendered but result is empty", 500
            return result
        except Exception as e:
            print(f"Error rendering template: {e}")
            import traceback
            traceback.print_exc()
            return f"Error loading template: {str(e)}", 500

    @app.route('/api/config', methods=['GET'])
    def get_config():
        """Get current configuration"""
        return jsonify(get_config_dict())

    @app.route('/api/config', methods=['POST'])
    def set_config():
        """Update configuration"""
        try:
            new_config = request.get_json()
            if update_config(new_config):
                # Trigger config reload in main loop
                global config_reload_needed
                config_reload_needed = True
                return jsonify({"success": True})
            else:
                return jsonify({"success": False, "error": "Failed to save configuration"}), 500
        except Exception as e:
            return jsonify({"success": False, "error": str(e)}), 400

    @app.route('/api/wifi/status', methods=['GET'])
    def wifi_status():
        """Get current WiFi status"""
        try:
            status = get_wifi_status()
            return jsonify(status)
        except Exception as e:
            return jsonify({"error": str(e)}), 500

    @app.route('/api/wifi/scan', methods=['GET'])
    def wifi_scan():
        """Scan for available WiFi networks"""
        try:
            networks = scan_wifi_networks()
            # If it's a dict with error, return as is, otherwise return as list
            if isinstance(networks, dict) and 'error' in networks:
                return jsonify(networks), 500
            return jsonify(networks if isinstance(networks, list) else [])
        except Exception as e:
            return jsonify({"error": str(e)}), 500

    @app.route('/api/wifi/connect', methods=['POST'])
    def wifi_connect():
        """Connect to a WiFi network"""
        try:
            data = request.get_json()
            ssid = data.get('ssid')
            password = data.get('password', '')
            
            if not ssid:
                return jsonify({"success": False, "error": "SSID is required"}), 400
            
            result = connect_to_wifi(ssid, password if password else None)
            return jsonify(result)
        except Exception as e:
            return jsonify({"success": False, "error": str(e)}), 500
    
    @app.route('/api/wifi/force-ap', methods=['POST'])
    def wifi_force_ap():
        """Force the device into Access Point mode by clearing WiFi config and rebooting"""
        try:
            # Run the force-ap-mode script in background (it will reboot)
            script_dir = os.path.dirname(os.path.abspath(__file__))
            script_path = os.path.join(script_dir, 'force-ap-mode.sh')
            
            if not os.path.exists(script_path):
                return jsonify({
                    "success": False, 
                    "error": "Force AP mode script not found"
                }), 500
            
            # Execute the script with sudo in background (it will reboot the device)
            # Use Popen to avoid waiting for reboot
            subprocess.Popen(
                ['sudo', '-n', 'bash', script_path],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True
            )
            
            # Return immediately - device will reboot
            return jsonify({
                "success": True,
                "message": "Clearing WiFi configuration and rebooting. Device will enter AP mode after reboot.",
                "ap_ssid": AP_SSID,
                "ap_ip": "192.168.4.1:8080",
                "reboot": True
            })
                
        except Exception as e:
            return jsonify({
                "success": False,
                "error": str(e)
            }), 500
    
    @app.route('/api/services/status', methods=['GET'])
    def services_status():
        """Get status of all OVBuddy services"""
        try:
            services = ['ovbuddy', 'ovbuddy-web', 'ovbuddy-wifi', 'avahi-daemon']
            status = {}
            for service in services:
                status[service] = get_service_status(service)
            return jsonify(status)
        except Exception as e:
            return jsonify({"error": str(e)}), 500
    
    @app.route('/api/services/<service_name>/<action>', methods=['POST'])
    def service_control(service_name, action):
        """Control a service (start, stop, restart)"""
        try:
            # Only allow control of OVBuddy services and avahi-daemon
            if service_name not in ['ovbuddy', 'ovbuddy-web', 'ovbuddy-wifi', 'avahi-daemon']:
                return jsonify({"success": False, "error": "Invalid service name"}), 400
            
            result = control_service(service_name, action)
            return jsonify(result)
        except Exception as e:
            return jsonify({"success": False, "error": str(e)}), 500

    @app.route('/api/version', methods=['GET'])
    def version_status():
        """Get version information and update status"""
        try:
            current_dir = os.path.dirname(os.path.abspath(__file__))
            script_path = os.path.join(current_dir, "ovbuddy.py")
            
            # Get running version (from memory)
            running_version = VERSION
            
            # Get file version (from disk)
            file_version = get_file_version(script_path)
            
            # Get update status
            update_status = get_update_status()
            
            # Check if file was updated but service hasn't restarted
            version_mismatch = file_version and file_version != running_version
            
            # Check for latest version on GitHub
            latest_version = None
            update_available = False
            try:
                update_available, latest_version = check_for_updates()
            except Exception:
                pass  # Don't fail the endpoint if version check fails
            
            return jsonify({
                "running_version": running_version,
                "file_version": file_version,
                "latest_version": latest_version,
                "version_mismatch": version_mismatch,
                "update_available": update_available,
                "update_status": update_status,
                "needs_restart": version_mismatch or update_status.get("update_in_progress", False)
            })
        except Exception as e:
            return jsonify({"error": str(e)}), 500

    @app.route('/api/shutdown', methods=['POST'])
    def shutdown_display():
        """Shutdown: Stop ovbuddy service, clear display, optionally display image"""
        try:
            # Check if file was uploaded
            image_file = None
            if 'image' in request.files:
                file = request.files['image']
                if file and file.filename:
                    # Validate file extension
                    if not file.filename.lower().endswith(('.jpg', '.jpeg', '.png')):
                        return jsonify({"success": False, "error": "Only JPG, JPEG, and PNG images are supported"}), 400
                    
                    # Save uploaded file temporarily
                    current_dir = os.path.dirname(os.path.abspath(__file__))
                    temp_dir = os.path.join(current_dir, "temp")
                    os.makedirs(temp_dir, exist_ok=True)
                    
                    # Generate unique filename
                    filename = f"shutdown_{uuid.uuid4().hex[:8]}.{file.filename.rsplit('.', 1)[1].lower()}"
                    image_path = os.path.join(temp_dir, filename)
                    file.save(image_path)
                    image_file = image_path
            
            # Stop ovbuddy service (not ovbuddy-web)
            stop_result = control_service('ovbuddy', 'stop')
            if not stop_result.get('success'):
                # Clean up uploaded file if service stop failed
                if image_file and os.path.exists(image_file):
                    try:
                        os.remove(image_file)
                    except:
                        pass
                return jsonify({
                    "success": False,
                    "error": f"Failed to stop ovbuddy service: {stop_result.get('error', 'Unknown error')}"
                }), 500
            
            # Clear display and optionally display image
            try:
                if TEST_MODE:
                    print("TEST MODE: Would clear display to white")
                    if image_file:
                        print(f"TEST MODE: Would display image: {image_file}")
                else:
                    # Check if display libraries are available
                    try:
                        import epd2in13_V4
                        from PIL import Image
                    except ImportError as e:
                        return jsonify({
                            "success": False,
                            "error": f"Display libraries not available: {e}"
                        }), 500
                    
                    # Initialize display
                    epd = epd2in13_V4.EPD()
                    epd.init()
                    
                    # Clear display to white
                    print("Clearing display to white...")
                    epd.Clear(0xFF)  # 0xFF = white
                    
                    # Display image if provided
                    if image_file:
                        print(f"Displaying image: {image_file}")
                        try:
                            # Load and process image
                            img = Image.open(image_file)
                            
                            # Convert to RGB if needed
                            if img.mode != 'RGB':
                                img = img.convert('RGB')
                            
                            # Resize to fit display (maintain aspect ratio)
                            img.thumbnail((DISPLAY_WIDTH, DISPLAY_HEIGHT), Image.Resampling.LANCZOS)
                            
                            # Create a new image with the exact display size (white background)
                            display_img = Image.new('RGB', (DISPLAY_WIDTH, DISPLAY_HEIGHT), color=(255, 255, 255))
                            
                            # Calculate position to center the image
                            x_offset = (DISPLAY_WIDTH - img.width) // 2
                            y_offset = (DISPLAY_HEIGHT - img.height) // 2
                            
                            # Paste the resized image onto the display-sized image
                            display_img.paste(img, (x_offset, y_offset))
                            
                            # Convert to grayscale
                            display_img = display_img.convert('L')
                            
                            # Convert to 1-bit (black/white) using threshold
                            threshold = 128
                            display_img = display_img.point(lambda x: 0 if x < threshold else 255, mode='1')
                            
                            # Apply inverted mode if enabled
                            if INVERTED:
                                display_img = display_img.point(lambda x: 0 if x == 255 else 255, mode='1')
                            
                            # Apply flip if enabled
                            if FLIP_DISPLAY:
                                display_img = display_img.rotate(180, expand=False)
                            
                            # Convert PIL image to display buffer
                            image_buffer = epd.getbuffer(display_img)
                            
                            # Display the image
                            epd.display(image_buffer)
                            
                            print("Image displayed successfully")
                        except Exception as e:
                            print(f"Error displaying image: {e}")
                            import traceback
                            traceback.print_exc()
                            # Continue even if image display fails
                    
                    # Put display to sleep
                    epd.sleep()
                    print("Display cleared and put to sleep")
                
                # Clean up uploaded file after displaying
                if image_file and os.path.exists(image_file):
                    try:
                        os.remove(image_file)
                    except:
                        pass
                
                return jsonify({
                    "success": True,
                    "message": "ovbuddy service stopped and display cleared" + (" (image displayed)" if image_file else "")
                })
            except Exception as e:
                # Clean up uploaded file on error
                if image_file and os.path.exists(image_file):
                    try:
                        os.remove(image_file)
                    except:
                        pass
                return jsonify({
                    "success": False,
                    "error": f"Failed to clear/update display: {str(e)}"
                }), 500
                
        except Exception as e:
            return jsonify({"success": False, "error": str(e)}), 500

    @app.route('/api/update', methods=['POST'])
    def trigger_update():
        """Trigger a system update"""
        global update_triggered, update_target_version
        
        try:
            data = request.get_json() or {}
            target_version = data.get('version', None)
            
            # Check if update is already in progress
            update_status = get_update_status()
            if update_status.get("update_in_progress"):
                return jsonify({
                    "success": False,
                    "error": "Update already in progress"
                }), 400
            
            # Check if an update is available
            update_available, latest_version = check_for_updates()
            if not update_available:
                # Check if user is forcing update to a specific version
                if not target_version:
                    return jsonify({
                        "success": False,
                        "error": "No update available"
                    }), 400
            
            # Use provided version or latest available
            version_to_update = target_version or latest_version
            
            # Set the trigger flag
            update_triggered = True
            update_target_version = version_to_update
            
            return jsonify({
                "success": True,
                "message": f"Update to v{version_to_update} triggered. The system will update and restart shortly.",
                "target_version": version_to_update
            })
        except Exception as e:
            return jsonify({"success": False, "error": str(e)}), 500

def start_web_server():
    """Start Flask web server in a separate thread.

    This can be called either from the main ovbuddy process or from a
    dedicated web-only helper so that the web UI / Bonjour can run
    independently of the display loop.
    """
    global zeroconf, service_info
    
    if not FLASK_AVAILABLE:
        print("Web server not available (Flask not installed)")
        print("  Install with: pip3 install flask")
        return
    
    def run_server():
        try:
            print(f"Starting Flask server on 0.0.0.0:8080...")
            app.run(host='0.0.0.0', port=8080, debug=False, use_reloader=False)
        except Exception as e:
            print(f"ERROR: Flask server failed to start: {e}")
            import traceback
            traceback.print_exc()
            raise
    
    # Start Flask in a daemon thread
    server_thread = threading.Thread(target=run_server, daemon=True, name="FlaskServer")
    server_thread.start()
    
    # Give Flask a moment to start and verify it's running
    time.sleep(0.5)
    if not server_thread.is_alive():
        print("ERROR: Flask server thread died immediately after starting!")
        print("This usually means Flask failed to bind to port 8080 or there's an import error.")
        print("Check if port 8080 is already in use: sudo netstat -tlnp | grep 8080")
        raise RuntimeError("Flask server thread failed to start")
    
    print("Flask server thread started successfully")
    
    # Register Bonjour/mDNS service
    if ZEROCONF_AVAILABLE:
        try:
            import socket
            hostname = socket.gethostname()
            
            # Get actual network IP address (not localhost)
            # Try to connect to a remote address to determine the local IP
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            try:
                # Connect to a remote address (doesn't actually send data)
                s.connect(('8.8.8.8', 80))
                local_ip = s.getsockname()[0]
            except Exception:
                # Fallback: try to get IP from hostname
                try:
                    local_ip = socket.gethostbyname(hostname)
                    # If it's localhost, try to get a real IP
                    if local_ip.startswith('127.'):
                        # Get IP from network interfaces
                        import subprocess
                        result = subprocess.run(['hostname', '-I'], capture_output=True, text=True, timeout=2)
                        if result.returncode == 0:
                            ips = result.stdout.strip().split()
                            if ips:
                                local_ip = ips[0]
                except Exception:
                    local_ip = '127.0.0.1'
            finally:
                s.close()
            
            zeroconf = Zeroconf()
            service_type = "_http._tcp.local."
            service_name = "ovbuddy._http._tcp.local."
            
            info = ServiceInfo(
                service_type,
                service_name,
                addresses=[socket.inet_aton(local_ip)],
                port=8080,
                properties={},
                server=f"{hostname}.local."
            )
            
            zeroconf.register_service(info)
            service_info = info
            print(f"Bonjour service registered: ovbuddy.local:8080 (IP: {local_ip})")
        except Exception as e:
            print(f"Warning: Could not register Bonjour service: {e}")
            print("Web server is still accessible via IP address")
    else:
        print("Bonjour service not available (zeroconf not installed)")
        print("  Install with: pip3 install zeroconf")

def stop_web_server():
    """Stop Bonjour service (if it was started)"""
    global zeroconf, service_info
    if zeroconf and service_info:
        try:
            zeroconf.unregister_service(service_info)
            zeroconf.close()
            print("Bonjour service unregistered")
        except Exception as e:
            print(f"Error unregistering Bonjour service: {e}")

# --------------------------
# MAIN LOOP
# --------------------------
# Global flag for immediate refresh trigger
refresh_triggered = False
config_reload_needed = False
update_triggered = False
update_target_version = None

def signal_handler(signum, frame):
    """Handle USR1 signal to trigger immediate refresh"""
    global refresh_triggered
    refresh_triggered = True
    print("Refresh signal received!")

def main(test_mode_arg=False, disable_web=False):
    global refresh_triggered, config_reload_needed, update_triggered, update_target_version
    
    # Load configuration from file
    load_config()
    
    # Initialize display early (before update check) so we can show update screen
    epd = None
    if TEST_MODE:
        print("Running in TEST MODE (no display hardware required)")
        print("Set TEST_MODE=0 to run with display hardware\n")
    else:
        # Initialize display with retry logic to handle GPIO busy errors
        print("Initializing display hardware...")
        max_retries = 5
        retry_delay = 2
        
        for attempt in range(max_retries):
            try:
                if epd is None:
                    epd = epd2in13_V4.EPD()
                epd.init()
                # Clear screen: use black if inverted, white if normal
                clear_color = 0x00 if INVERTED else 0xFF
                epd.Clear(clear_color)
                print("Display initialized and cleared")
                # Show loading screen immediately
                render_loading_screen(epd, test_mode=test_mode_arg)
                break
            except Exception as e:
                error_msg = str(e)
                if "GPIO busy" in error_msg or "busy" in error_msg.lower():
                    if attempt < max_retries - 1:
                        print(f"GPIO pins busy (attempt {attempt + 1}/{max_retries}), waiting {retry_delay}s before retry...")
                        time.sleep(retry_delay)
                        # Try to clean up any existing GPIO state
                        try:
                            if epd:
                                epd.sleep()
                        except:
                            pass
                        epd = None
                        continue
                    else:
                        print(f"ERROR: Failed to initialize display after {max_retries} attempts: {e}")
                        print("GPIO pins appear to be in use by another process.")
                        print("Try: sudo systemctl stop ovbuddy && sleep 2 && sudo systemctl start ovbuddy")
                        # Continue without display - update can still proceed
                        epd = None
                        break
                else:
                    # Different error, don't retry
                    print(f"ERROR: Failed to initialize display: {e}")
                    # Continue without display - update can still proceed
                    epd = None
                    break
    
    # Check and clear update status on startup
    update_status = get_update_status()
    if update_status.get("update_in_progress"):
        # If update was marked as in progress but we're starting, it may have been interrupted
        # Clear it and mark as potentially failed
        print("⚠ Previous update may have been interrupted")
        set_update_status(in_progress=False, success=False)
    elif update_status.get("last_update_success") and update_status.get("last_update_version"):
        # If last update was successful, we're likely running the new version now
        # Clear the status (update completed)
        print(f"✓ Last update to v{update_status.get('last_update_version')} was successful")
        # Don't clear it completely, just mark as not in progress
    
    # Check for updates on startup
    print("\n" + "="*50)
    print(f"OVBuddy v{VERSION}")
    print("="*50)
    try:
        update_available, latest_version = check_for_updates()
        if update_available and latest_version:
            if AUTO_UPDATE:
                print(f"\n🎉 Update available: v{VERSION} -> v{latest_version}")
                print("Auto-update enabled. Attempting to update...")
                
                if perform_update(UPDATE_REPOSITORY_URL, latest_version, epd=epd, test_mode=test_mode_arg):
                    print("\n✓ Update successful!")
                print("Reinstalling services and restarting...")
                
                # Get current directory (where install-service.sh should be)
                current_dir = os.path.dirname(os.path.abspath(__file__))
                install_script = os.path.join(current_dir, "install-service.sh")
                
                # Try to reinstall services using install-service.sh (updates service files and restarts both services)
                services_restarted = False
                
                if os.path.exists(install_script):
                    print("Found install-service.sh, attempting to reinstall services...")
                    try:
                        # Check if we're running as a systemd service
                        result = subprocess.run(['systemctl', 'is-active', 'ovbuddy'], 
                                              capture_output=True, text=True, timeout=5)
                        if result.stdout.strip() == 'active':
                            print("Detected systemd service, running install-service.sh...")
                            # Run install-service.sh with sudo (requires passwordless sudo)
                            install_result = subprocess.run(
                                ['sudo', '-n', 'bash', install_script],
                                cwd=current_dir,
                                capture_output=True,
                                text=True,
                                timeout=60
                            )
                            
                            if install_result.returncode == 0:
                                print("✓ Services reinstalled and restarted successfully")
                                services_restarted = True
                                # Show rebooting message
                                render_update_screen(epd, "Rebooting...", latest_version, test_mode_arg)
                                time.sleep(2)  # Give user time to see the message
                                # Exit to allow services to restart cleanly
                                sys.exit(0)
                            else:
                                print(f"⚠ install-service.sh failed (exit code {install_result.returncode})")
                                print(f"stdout: {install_result.stdout}")
                                print(f"stderr: {install_result.stderr}")
                                print("Falling back to manual service restart...")
                    except subprocess.TimeoutExpired:
                        print("⚠ install-service.sh timed out")
                        print("Falling back to manual service restart...")
                    except FileNotFoundError:
                        print("⚠ sudo not available or passwordless sudo not configured")
                        print("Falling back to manual service restart...")
                    except Exception as e:
                        print(f"⚠ Error running install-service.sh: {e}")
                        print("Falling back to manual service restart...")
                
                # Fallback: manually restart all services if install-service.sh didn't work
                if not services_restarted:
                    try:
                        result = subprocess.run(['systemctl', 'is-active', 'ovbuddy'], 
                                              capture_output=True, text=True, timeout=5)
                        if result.stdout.strip() == 'active':
                            print("Restarting services manually...")
                            
                            # Restart ovbuddy service
                            subprocess.run(['sudo', '-n', 'systemctl', 'restart', 'ovbuddy'], 
                                         timeout=10, check=False)
                            
                            # Check if ovbuddy-web service exists and restart it too
                            web_check = subprocess.run(['systemctl', 'is-active', 'ovbuddy-web'], 
                                                      capture_output=True, text=True, timeout=5)
                            if web_check.stdout.strip() == 'active':
                                subprocess.run(['sudo', '-n', 'systemctl', 'restart', 'ovbuddy-web'], 
                                             timeout=10, check=False)
                                print("✓ ovbuddy and ovbuddy-web services restarted")
                            else:
                                print("✓ ovbuddy service restarted (ovbuddy-web not active)")
                            
                            # Check if ovbuddy-wifi service exists and restart it too
                            wifi_check = subprocess.run(['systemctl', 'is-active', 'ovbuddy-wifi'], 
                                                       capture_output=True, text=True, timeout=5)
                            if wifi_check.stdout.strip() == 'active':
                                subprocess.run(['sudo', '-n', 'systemctl', 'restart', 'ovbuddy-wifi'], 
                                             timeout=10, check=False)
                                print("✓ ovbuddy-wifi service also restarted")
                            
                            # Show rebooting message
                            render_update_screen(epd, "Rebooting...", latest_version, test_mode_arg)
                            time.sleep(2)  # Give user time to see the message
                            # Exit to allow restart
                            sys.exit(0)
                    except Exception as e:
                        print(f"⚠ Could not restart services automatically: {e}")
                        print("Please restart manually:")
                        print("  sudo systemctl restart ovbuddy")
                        print("  sudo systemctl restart ovbuddy-web")
                        print("  sudo bash install-service.sh  # To update service files")
                else:
                    print("\n✗ Update failed, continuing with current version")
            else:
                print(f"\n📦 Update available: v{VERSION} -> v{latest_version}")
                print("Auto-update is disabled. Use the web interface to update manually.")
        else:
            print("✓ Running the latest version")
    except Exception as e:
        print(f"Error during update check: {e}")
        print("Continuing with current version...")
    print("="*50 + "\n")
    
    # Optionally start web server / Bonjour
    if not disable_web:
        start_web_server()
    
    # Set up signal handler for USR1 (refresh trigger)
    signal.signal(signal.SIGUSR1, signal_handler)
    
    if test_mode_arg:
        print("Running with MOCK DATA (--test argument)")
        print("Using 'Zürich Saalsporthalle' as station with mock departures\n")
    
    # Display is already initialized earlier (before update check)
    # epd variable is already set above
    first_successful_fetch = False  # Track if we've done first successful fetch

    update_count = 0
    last_was_successful = False  # Track if last fetch was successful (no error)
    is_first_refresh = True  # Track if this is the very first refresh attempt
    last_ap_active = None  # Track AP state transitions for cleaner logs
    last_ap_screen_key = None  # Avoid re-rendering AP QR screen unnecessarily
    try:
        while True:
            # Check for update trigger (from web interface)
            if update_triggered:
                target_version = update_target_version
                update_triggered = False
                update_target_version = None
                
                print("\n" + "="*50)
                print(f"UPDATE TRIGGERED FROM WEB INTERFACE")
                print(f"Target version: {target_version}")
                print("="*50)
                
                if perform_update(UPDATE_REPOSITORY_URL, target_version, epd=epd, test_mode=test_mode_arg):
                    print("\n✓ Update successful!")
                    print("Reinstalling services and restarting...")
                    
                    # Get current directory (where install-service.sh should be)
                    current_dir = os.path.dirname(os.path.abspath(__file__))
                    install_script = os.path.join(current_dir, "install-service.sh")
                    
                    # Try to reinstall services using install-service.sh
                    services_restarted = False
                    
                    if os.path.exists(install_script):
                        print("Found install-service.sh, attempting to reinstall services...")
                        try:
                            # Check if we're running as a systemd service
                            result = subprocess.run(['systemctl', 'is-active', 'ovbuddy'], 
                                                  capture_output=True, text=True, timeout=5)
                            if result.stdout.strip() == 'active':
                                print("Detected systemd service, running install-service.sh...")
                                install_result = subprocess.run(
                                    ['sudo', '-n', 'bash', install_script],
                                    cwd=current_dir,
                                    capture_output=True,
                                    text=True,
                                    timeout=60
                                )
                                
                                if install_result.returncode == 0:
                                    print("✓ Services reinstalled and restarted successfully")
                                    services_restarted = True
                                    render_update_screen(epd, "Rebooting...", target_version, test_mode_arg)
                                    time.sleep(2)
                                    sys.exit(0)
                                else:
                                    print(f"⚠ install-service.sh failed (exit code {install_result.returncode})")
                                    print("Falling back to manual service restart...")
                        except Exception as e:
                            print(f"⚠ Error running install-service.sh: {e}")
                            print("Falling back to manual service restart...")
                    
                    # Fallback: manually restart both services
                    if not services_restarted:
                        try:
                            result = subprocess.run(['systemctl', 'is-active', 'ovbuddy'], 
                                                  capture_output=True, text=True, timeout=5)
                            if result.stdout.strip() == 'active':
                                print("Restarting services manually...")
                                subprocess.run(['sudo', '-n', 'systemctl', 'restart', 'ovbuddy'], 
                                             timeout=10, check=False)
                                web_check = subprocess.run(['systemctl', 'is-active', 'ovbuddy-web'], 
                                                          capture_output=True, text=True, timeout=5)
                                if web_check.stdout.strip() == 'active':
                                    subprocess.run(['sudo', '-n', 'systemctl', 'restart', 'ovbuddy-web'], 
                                                 timeout=10, check=False)
                                    print("✓ Both services restarted")
                                else:
                                    print("✓ ovbuddy service restarted (ovbuddy-web not active)")
                                
                                render_update_screen(epd, "Rebooting...", target_version, test_mode_arg)
                                time.sleep(2)
                                sys.exit(0)
                        except Exception as e:
                            print(f"⚠ Could not restart services automatically: {e}")
                            print("Please restart manually:")
                            print("  sudo systemctl restart ovbuddy")
                            print("  sudo systemctl restart ovbuddy-web")
                else:
                    print("\n✗ Update failed, continuing with current version")
                    # Error will be visible in web interface via version status endpoint
            
            # Check for config reload
            if config_reload_needed:
                load_config()
                config_reload_needed = False
                print("Configuration reloaded from file")
                # Trigger immediate refresh to show new config
                refresh_triggered = True
            
            # Check for trigger file (alternative method)
            trigger_file = "/home/pi/ovbuddy/.refresh_trigger"
            if os.path.exists(trigger_file):
                refresh_triggered = True
                os.remove(trigger_file)  # Remove trigger file
            
            # Periodically check for config file changes
            load_config()  # This will only reload if file was modified

            # If we're in Access Point mode, keep the QR/AP screen pinned and
            # skip the departure board / API fetches until AP mode ends.
            ap_active_now = is_access_point_mode_active()
            if ap_active_now:
                if last_ap_active is not True:
                    print("\n[Access Point mode detected] Pinning QR screen (SSID/password) until WiFi is configured.")
                last_ap_active = True
                # Only re-render if AP UI info changes (SSID/password visibility/IP).
                ap_info = get_access_point_ui_info()
                pwd_display = ap_info["password"] if ap_info.get("display_password") else ("********" if ap_info.get("password") else "")
                ap_screen_key = (ap_info.get("ssid", ""), pwd_display, bool(ap_info.get("display_password")), ap_info.get("ip", ""))

                if last_ap_screen_key != ap_screen_key:
                    try:
                        render_qr_code(epd, test_mode=test_mode_arg)
                    except Exception as e:
                        print(f"Error displaying AP QR screen: {e}")
                    last_ap_screen_key = ap_screen_key

                # Poll AP mode periodically; avoid e-ink flashing by not re-rendering.
                time.sleep(5)
                continue
            else:
                if last_ap_active is True:
                    print("\n[Access Point mode exited] Resuming normal departure display.")
                last_ap_active = False
                last_ap_screen_key = None
            
            # If refresh triggered or normal interval, update
            if refresh_triggered:
                print("\n--- Immediate refresh triggered ---")
                refresh_triggered = False
            else:
                update_count += 1
                print(f"\n--- Update #{update_count} ---")
            
            # Use mock data if -test argument was provided
            if test_mode_arg:
                mock_data = generate_mock_departures()
                # Add station name to each departure (same as real API)
                for dep in mock_data:
                    dep["_station"] = "Zürich Saalsporthalle"
                # Process mock data the same way as real API data
                # Filter by lines
                filtered = [entry for entry in mock_data if matches_line(entry["number"], LINES)]
                # Sort by departure time
                filtered.sort(key=lambda x: x["stop"]["departure"])
                # If no filtered results but we have departures, return all (same as real API)
                if not filtered and mock_data:
                    print("No matches for selected lines, showing all departures")
                    mock_data.sort(key=lambda x: x["stop"]["departure"])
                    departures = mock_data
                else:
                    departures = filtered
                error_msg = None
            else:
                departures, error_msg = fetch_departures(STATIONS)
            
            # Track if this is a successful fetch (has departures, no error message)
            is_successful = departures and error_msg is None
            
            # Determine if this is first successful fetch
            is_first_successful = first_successful_fetch == False and is_successful
            
            # If this is the first refresh, show QR code first
            if is_first_refresh:
                # Show QR code if duration is > 0
                if QR_CODE_DISPLAY_DURATION > 0:
                    try:
                        print("Showing QR code...")
                        render_qr_code(epd, test_mode=test_mode_arg)
                        print(f"Showing QR code for {QR_CODE_DISPLAY_DURATION} seconds...")
                        time.sleep(QR_CODE_DISPLAY_DURATION)
                        print("QR code display complete")
                    except Exception as e:
                        print(f"Error displaying QR code: {e}")
                        print("Continuing without QR code display...")
                else:
                    print("QR code display skipped (duration set to 0)")
                
                print("Fetching departures now...")
                # Mark that we've done the QR code display
                is_first_refresh = False
                # Continue to next iteration to fetch immediately
                continue
            
            render_board(departures, epd, error_msg, 
                        is_first_successful=is_first_successful,
                        last_was_successful=last_was_successful,
                        test_mode=test_mode_arg)
            
            # Mark that we've done at least one refresh
            if is_first_refresh:
                is_first_refresh = False
            
            # Update tracking
            if is_successful and not first_successful_fetch:
                first_successful_fetch = True
                print("First successful fetch completed - will use partial refresh for future successful updates")
            
            # Update last_was_successful for next iteration
            last_was_successful = is_successful
            
            # Sleep, but check for trigger more frequently
            sleep_interval = 1  # Check every second
            slept = 0
            while slept < REFRESH_INTERVAL and not refresh_triggered:
                time.sleep(sleep_interval)
                slept += sleep_interval
                # Check for trigger file during sleep
                if os.path.exists(trigger_file):
                    refresh_triggered = True
                    os.remove(trigger_file)
                    break
    except KeyboardInterrupt:
        print("\nShutting down...")
    except Exception as e:
        print(f"Error in main loop: {e}")
        import traceback
        traceback.print_exc()
    finally:
        # Stop web server (if it was started)
        if not disable_web and FLASK_AVAILABLE:
            stop_web_server()
        
        # Only sleep/close display when we're done
        if epd and not TEST_MODE:
            try:
                print("Putting display to sleep...")
                epd.sleep()
            except Exception as e:
                print(f"Error putting display to sleep: {e}")

if __name__ == "__main__":
    # Parse command line arguments
    parser = argparse.ArgumentParser(description='OVBuddy e-ink display for public transport')
    parser.add_argument('-test', '--test', action='store_true', 
                        help='Run with mock data instead of fetching from API')
    parser.add_argument('--no-web', action='store_true',
                        help='Do not start the web server / Bonjour service (display only)')
    args = parser.parse_args()
    
    # Pass arguments to main function
    main(test_mode_arg=args.test, disable_web=args.no_web)

