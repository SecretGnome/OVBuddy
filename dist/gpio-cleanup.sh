#!/bin/bash
# GPIO Cleanup Script
# Releases GPIO pins that may be held by previous processes
# This script should be run before starting the ovbuddy service

# GPIO pins used by the e-ink display
GPIO_PINS=(17 18 24 25)

echo "Releasing GPIO pins..."

for pin in "${GPIO_PINS[@]}"; do
    # Try to release the pin using gpioset (if available)
    if command -v gpioset &> /dev/null; then
        # Set pin to input mode to release it
        gpioset -z gpiochip0 $pin=0 2>/dev/null || true
    fi
    
    # Also try using the sysfs interface (legacy method)
    if [ -d "/sys/class/gpio/gpio${pin}" ]; then
        echo "$pin" > /sys/class/gpio/unexport 2>/dev/null || true
    fi
done

# Give the system a moment to release the pins
sleep 0.5

echo "GPIO cleanup complete"

