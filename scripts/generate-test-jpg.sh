#!/bin/bash

# Script to generate a JPG image of the mock/test output locally
# This renders the board with mock data and saves it as a JPG file

# Change to project root directory (parent of scripts/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default output filename
OUTPUT_FILE="${1:-test-output.jpg}"

# Check if dist/ovbuddy.py exists
if [ ! -f "dist/ovbuddy.py" ]; then
    echo -e "${RED}Error: dist/ovbuddy.py not found!${NC}"
    echo "Please run this script from the project root directory."
    exit 1
fi

echo -e "${YELLOW}Generating test output as JPG...${NC}"
echo "Output file: $OUTPUT_FILE"
echo ""

# Export variables for Python script
export PROJECT_ROOT
export OUTPUT_FILE

# Run Python script to generate the image
# This script will import ovbuddy, generate mock data, render the board, and save as JPG
python3 << PYTHON_SCRIPT
import sys
import os

# Get project root from environment (set by bash script)
PROJECT_ROOT = os.environ.get('PROJECT_ROOT', os.getcwd())
DIST_DIR = os.path.join(PROJECT_ROOT, 'dist')

# Add dist directory to path so we can import ovbuddy
sys.path.insert(0, DIST_DIR)

# Mock hardware modules before importing ovbuddy to avoid hardware dependencies
# Create a minimal mock for epd2in13_V4
class MockEPDClass:
    def __init__(self):
        pass
    def init(self):
        pass
    def getbuffer(self, image):
        return b''
    def display(self, buffer):
        pass
    def displayPartial(self, buffer):
        pass
    def Clear(self, color):
        pass
    def sleep(self):
        pass

# Mock the epd2in13_V4 module
import types
mock_epd_module = types.ModuleType('epd2in13_V4')
mock_epd_module.EPD = MockEPDClass
sys.modules['epd2in13_V4'] = mock_epd_module

# Mock epdconfig module (might be imported by epd2in13_V4)
mock_epdconfig = types.ModuleType('epdconfig')
sys.modules['epdconfig'] = mock_epdconfig

# Set TEST_MODE=0 so it renders an image (not just console output)
os.environ['TEST_MODE'] = '0'

# Import ovbuddy module (it will use our mocked hardware modules)
import ovbuddy

# Load configuration
ovbuddy.load_config()

# Generate mock departures
mock_data = ovbuddy.generate_mock_departures()

# Add station name to each departure (same as real API)
for dep in mock_data:
    dep["_station"] = "Zürich Saalsporthalle"

# Filter by lines
filtered = [entry for entry in mock_data if ovbuddy.matches_line(entry["number"], ovbuddy.LINES)]

# Sort by departure time
filtered.sort(key=lambda x: x["stop"]["departure"])

# If no filtered results but we have departures, return all
if not filtered and mock_data:
    print("No matches for selected lines, showing all departures")
    mock_data.sort(key=lambda x: x["stop"]["departure"])
    departures = mock_data
else:
    departures = filtered

# Create a mock EPD object that captures the image instead of displaying it
class MockEPD:
    def __init__(self):
        self.captured_image = None
    
    def init(self):
        pass
    
    def getbuffer(self, image):
        # Capture the image (make a copy since it might be modified)
        # The image is already rotated if FLIP_DISPLAY is enabled at this point
        from PIL import Image
        self.captured_image = image.copy()
        return b''  # Return empty buffer
    
    def display(self, buffer):
        pass
    
    def displayPartial(self, buffer):
        pass
    
    def Clear(self, color):
        pass
    
    def sleep(self):
        pass

# Create mock EPD
mock_epd = MockEPD()

# Render the board (this will create the image and try to display it)
# We'll capture the image from the mock EPD
ovbuddy.render_board(
    departures=departures,
    epd=mock_epd,
    error_msg=None,
    is_first_successful=False,
    last_was_successful=False,
    test_mode=False
)

# Get the captured image
if mock_epd.captured_image is None:
    print("Error: Image was not captured. The render_board function may have changed.")
    sys.exit(1)

# Convert 1-bit image to RGB for JPG
# Note: The image is already rotated if FLIP_DISPLAY is enabled (handled in render_board)
image = mock_epd.captured_image

# Convert to RGB (JPG doesn't support 1-bit mode)
rgb_image = image.convert('RGB')

# Save as JPG
output_file = os.environ.get('OUTPUT_FILE', 'test-output.jpg')
rgb_image.save(output_file, 'JPEG', quality=95)

print(f"✓ Image saved to: {output_file}")
print(f"  Dimensions: {rgb_image.width}x{rgb_image.height}")
PYTHON_SCRIPT

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully generated test output as JPG!${NC}"
    echo "  File: $OUTPUT_FILE"
else
    echo -e "${RED}✗ Failed to generate JPG${NC}"
    exit 1
fi

