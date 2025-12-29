# eInk simulator (macOS)

OVBuddy supports a PIL-backed **simulator output backend** that:
- writes a single PNG frame (overwritten each refresh)
- can show a live-updating window (Tkinter)

## Run (window + PNG)

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

## Window options

- **Disable window** (PNG only):

```bash
OVBUDDY_SIM_WINDOW=0 ./scripts/run-macos-sim.sh
```

- **Scale factor** (default 3×):

```bash
OVBUDDY_SIM_SCALE=4 ./scripts/run-macos-sim.sh
```

## Requirements

The simulator needs:
- Pillow (`PIL`)
- Tkinter (for the window)
