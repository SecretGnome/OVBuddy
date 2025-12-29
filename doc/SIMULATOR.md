# eInk simulator (macOS)

OVBuddy supports a **simulator output backend** that writes frames to a PNG.

A separate viewer (`dist/eink_simulator.py`) watches that PNG and shows a live-updating window.

## Run (viewer + PNG)

```bash
chmod +x ./scripts/run-macos-sim.sh
./scripts/run-macos-sim.sh
```

Mock data:

```bash
./scripts/run-macos-sim.sh --test
```

## Output files

- **Default PNG path**: `dist/sim-output.png`
- Override:

```bash
OVBUDDY_SIM_OUT=/tmp/ovbuddy.png ./scripts/run-macos-sim.sh
```

## Display options (simulated panel)

These affect both rendering (OVBuddy) and the viewer window:

- **Width / height** (pixels):

```bash
OVBUDDY_SIM_WIDTH=250 OVBUDDY_SIM_HEIGHT=122 ./scripts/run-macos-sim.sh
```

- **pixelDensity** (viewer scale factor; default 3):

```bash
OVBUDDY_SIM_PIXEL_DENSITY=4 ./scripts/run-macos-sim.sh
```

## Font (make simulator match the Pi)

On the Pi, OVBuddy usually uses a TrueType font from `/usr/share/fonts/...` (typically DejaVu).
On macOS those paths don’t exist, so without configuration the simulator may fall back to a small
default bitmap font (and look different).

You can override fonts explicitly:

```bash
OVBUDDY_FONT_REGULAR="/path/to/DejaVuSans.ttf" \
OVBUDDY_FONT_BOLD="/path/to/DejaVuSans-Bold.ttf" \
./scripts/run-macos-sim.sh
```

## Viewer options

- **Disable viewer** (PNG only):

```bash
OVBUDDY_SIM_VIEWER=0 ./scripts/run-macos-sim.sh
```

If the Tk window doesn’t appear on your machine (Tk issues), force the **browser viewer**:

```bash
OVBUDDY_SIM_VIEWER_MODE=http ./scripts/run-macos-sim.sh
```

It will print a local URL like `http://127.0.0.1:8765/` and (by default) open it automatically.

You can also run the viewer directly:

```bash
python3 dist/eink_simulator.py --input dist/sim-output.png --width 250 --height 122 --pixel-density 3
```

## Requirements

The simulator needs:
- Pillow (`PIL`)
- Tkinter (for the window)
