#!/usr/bin/env python3
"""
Display an image on the e-ink display
Takes an image file path as argument and displays it on the screen
"""
import os
import sys

# Test mode: set TEST_MODE=1 environment variable to run without display hardware
TEST_MODE = os.getenv("TEST_MODE", "0") == "1"

if not TEST_MODE:
    from PIL import Image
    import epd2in13_V4

# Display dimensions (from ovbuddy.py)
DISPLAY_WIDTH = 250
DISPLAY_HEIGHT = 122

# Configuration (can be overridden by environment variables)
INVERTED = os.getenv("INVERTED", "0") == "1"  # Set to True for white text on black background
FLIP_DISPLAY = os.getenv("FLIP_DISPLAY", "0") == "1"  # Set to True to rotate display 180 degrees

def display_image(image_path):
    """Display an image on the e-ink display"""
    if TEST_MODE:
        print(f"Running in TEST MODE (no display hardware required)")
        print(f"Would display image: {image_path}")
        print(f"Image would be resized to {DISPLAY_WIDTH}x{DISPLAY_HEIGHT}")
        if INVERTED:
            print("Display mode: INVERTED (white on black)")
        if FLIP_DISPLAY:
            print("Display mode: FLIP_DISPLAY (rotated 180 degrees)")
        return
    
    # Load and process image
    print(f"Loading image: {image_path}")
    try:
        img = Image.open(image_path)
    except Exception as e:
        print(f"Error loading image: {e}")
        return
    
    # Convert to RGB if needed (handles RGBA, P, etc.)
    if img.mode != 'RGB':
        img = img.convert('RGB')
    
    # Resize to fit display (maintain aspect ratio, then crop/center)
    img.thumbnail((DISPLAY_WIDTH, DISPLAY_HEIGHT), Image.Resampling.LANCZOS)
    
    # Create a new image with the exact display size
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
    
    # Initialize display
    print("Initializing display...")
    epd = epd2in13_V4.EPD()
    epd.init()
    
    # Clear display first
    clear_color = 0x00 if INVERTED else 0xFF
    epd.Clear(clear_color)
    
    # Convert PIL image to display buffer
    print("Displaying image...")
    image_buffer = epd.getbuffer(display_img)
    
    # Display the image
    epd.display(image_buffer)
    
    # Put display to sleep
    print("Putting display to sleep...")
    epd.sleep()
    
    print("Image displayed successfully!")

def main():
    if len(sys.argv) < 2:
        print("Usage: display_image.py <image_path>")
        print("Environment variables:")
        print("  INVERTED=1       - Invert colors (white on black)")
        print("  FLIP_DISPLAY=1   - Rotate display 180 degrees")
        print("  TEST_MODE=1       - Run without display hardware")
        sys.exit(1)
    
    image_path = sys.argv[1]
    
    if not os.path.exists(image_path):
        print(f"Error: Image file not found: {image_path}")
        sys.exit(1)
    
    try:
        display_image(image_path)
    except KeyboardInterrupt:
        print("\nInterrupted by user")
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    main()

