#!/usr/bin/env python3

"""
Display Access Point information on the e-ink screen.
This script is called by wifi-monitor.py when switching to AP mode.
"""

import sys
import os
import json

# Add the current directory to the path so we can import ovbuddy
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Import the render function from ovbuddy
try:
    from ovbuddy import render_ap_info, load_config, INVERTED, FLIP_DISPLAY
    import epd2in13_V4
    DISPLAY_AVAILABLE = True
except ImportError as e:
    print(f"Warning: Could not import display modules: {e}")
    DISPLAY_AVAILABLE = False


def main():
    """Display AP information on the e-ink screen"""
    
    if not DISPLAY_AVAILABLE:
        print("Display modules not available, exiting")
        sys.exit(1)
    
    # Load configuration
    config_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), "config.json")
    
    try:
        with open(config_file, 'r') as f:
            config = json.load(f)
    except Exception as e:
        print(f"Error loading config: {e}")
        config = {}
    
    # Get AP settings
    ssid = config.get('ap_ssid', 'OVBuddy')
    password = config.get('ap_password', '')
    display_password = config.get('display_ap_password', False)
    
    print(f"Displaying AP info: SSID={ssid}, show_password={display_password}")
    
    try:
        # Initialize display
        epd = epd2in13_V4.EPD()
        epd.init()
        
        # Render AP info
        render_ap_info(ssid, password, display_password, epd=epd, test_mode=False)
        
        # Don't sleep the display - leave it showing the AP info
        # epd.sleep()
        
        print("AP info displayed successfully")
        
    except Exception as e:
        print(f"Error displaying AP info: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()




