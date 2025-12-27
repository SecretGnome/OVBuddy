#!/usr/bin/env python3
"""
Show a simple "ready to deploy" message on the Waveshare 2.13" V4 e-ink display.

Intended to be called during SD-card first-boot provisioning (before OVBuddy is deployed).
"""

import os
import sys


def main() -> int:
    try:
        # Ensure we can import the driver modules when executed from arbitrary locations.
        script_dir = os.path.dirname(os.path.abspath(__file__))
        sys.path.insert(0, script_dir)

        import epd2in13_V4  # type: ignore
        from PIL import Image, ImageDraw, ImageFont  # type: ignore

        display_width = 250
        display_height = 122

        epd = epd2in13_V4.EPD()
        epd.init()

        image = Image.new("1", (display_width, display_height), 255)
        draw = ImageDraw.Draw(image)
        font = ImageFont.load_default()

        lines = [
            "OVBuddy",
            "",
            "SD setup complete",
            "Ready to deploy",
            "",
            "Run: ./scripts/deploy.sh",
        ]

        line_height = 12
        total_h = len(lines) * line_height
        y = max(0, (display_height - total_h) // 2)

        for line in lines:
            try:
                bbox = draw.textbbox((0, 0), line, font=font)
                w = bbox[2] - bbox[0]
            except Exception:
                w = len(line) * 6
            x = max(0, (display_width - w) // 2)
            draw.text((x, y), line, font=font, fill=0)
            y += line_height

        epd.display(epd.getbuffer(image))
        return 0
    except Exception as e:
        # Never block boot; just print a diagnostic and exit successfully.
        print(f"[ovbuddy_eink_ready] Could not display ready message: {e}")
        return 0


if __name__ == "__main__":
    raise SystemExit(main())




