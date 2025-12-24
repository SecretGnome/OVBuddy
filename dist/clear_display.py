#!/usr/bin/env python3
"""
Clear the e-ink display - fills it with white
"""
import os

# Test mode: set TEST_MODE=1 environment variable to run without display hardware
TEST_MODE = os.getenv("TEST_MODE", "0") == "1"

if not TEST_MODE:
    import epd2in13_V4

def main():
    if TEST_MODE:
        print("Running in TEST MODE (no display hardware required)")
        print("Would clear display (fill with white) if running on Raspberry Pi")
        return
    
    print("Initializing display...")
    epd = epd2in13_V4.EPD()
    epd.init()
    
    print("Clearing display (filling with white)...")
    epd.Clear(0xFF)  # 0xFF = white
    
    print("Putting display to sleep...")
    epd.sleep()
    
    print("Display cleared successfully!")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nInterrupted by user")
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()

