#!/usr/bin/env python3
"""
GPIO Cleanup Script
Releases GPIO pins that may be held by previous processes using lgpio
This script should be run before starting the ovbuddy service
"""

import sys

try:
    import lgpio
except ImportError:
    print("lgpio not available, skipping GPIO cleanup")
    sys.exit(0)

# GPIO pins used by the e-ink display
GPIO_PINS = [17, 18, 24, 25]

print("Releasing GPIO pins using lgpio...")

try:
    # Open GPIO chip
    h = lgpio.gpiochip_open(0)
    
    # Try to free each pin
    for pin in GPIO_PINS:
        try:
            # The pin might not be claimed, which will raise an error - that's OK
            lgpio.gpio_free(h, pin)
            print(f"  Released GPIO {pin}")
        except Exception as e:
            # Pin wasn't claimed or already free - this is fine
            pass
    
    # Close the chip handle
    lgpio.gpiochip_close(h)
    print("GPIO cleanup complete")
    
except Exception as e:
    print(f"GPIO cleanup error (this may be normal): {e}")
    # Don't fail the service start if cleanup fails
    sys.exit(0)

