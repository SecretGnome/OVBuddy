#!/usr/bin/env python3

"""
Standalone web / Bonjour service for OVBuddy.

This module starts only the Flask web UI and Bonjour (zeroconf) advertisement
and then keeps running. It allows the web interface to stay available at
ovbuddy.local:8080 even when the main ovbuddy display service is stopped.

The existing ovbuddy.py script continues to handle the e-ink display loop.
"""

import sys
import time
import traceback

try:
    from ovbuddy import load_config, start_web_server, stop_web_server, FLASK_AVAILABLE
except ImportError as e:
    print(f"ERROR: Failed to import from ovbuddy module: {e}")
    print("Make sure ovbuddy.py is in the same directory")
    traceback.print_exc()
    sys.exit(1)


def main():
    print("Starting OVBuddy web service...")
    
    # Check if Flask is available
    if not FLASK_AVAILABLE:
        print("ERROR: Flask is not available!")
        print("Install with: pip3 install flask")
        sys.exit(1)
    
    try:
        # Ensure configuration is loaded so the web UI has current values
        print("Loading configuration...")
        load_config()
        print("Configuration loaded")
        
        # Start Flask + Bonjour in background threads
        print("Starting web server and Bonjour service...")
        start_web_server()
        
        # Give Flask a moment to start
        time.sleep(2)
        
        print("Web service started successfully!")
        print("Web interface should be available at:")
        print("  - http://ovbuddy.local:8080 (via Bonjour)")
        print("  - http://<ip-address>:8080 (direct IP)")
        
        # Keep process alive indefinitely; web server runs in background thread
        while True:
            time.sleep(60)
    except KeyboardInterrupt:
        print("\nShutting down ovbuddy web service...")
    except Exception as e:
        print(f"ERROR: Unexpected error in web service: {e}")
        traceback.print_exc()
        sys.exit(1)
    finally:
        # Cleanly unregister Bonjour service
        print("Stopping web service...")
        stop_web_server()
        print("Web service stopped")


if __name__ == "__main__":
    main()


