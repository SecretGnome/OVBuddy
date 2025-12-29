# Terminal preview (macOS)

You can run OVBuddy on macOS **in a terminal** (no e-ink hardware) to preview the layout.

## Run

```bash
./scripts/run-macos.sh
```

This runs:
- `dist/ovbuddy.py` with `TEST_MODE=1` (no hardware)
- the **terminal display backend** (`OVBUDDY_OUTPUT=terminal`)
- `--no-web` by default (no Flask/Bonjour needed)

### Mock departures

```bash
./scripts/run-macos.sh --test
```

## Configure

Edit `dist/config.json` (same keys as on the Pi):
- `stations`
- `lines`
- `refresh_interval`

## Tips

- If the script isn’t executable yet:

```bash
chmod +x ./scripts/run-macos.sh
```
