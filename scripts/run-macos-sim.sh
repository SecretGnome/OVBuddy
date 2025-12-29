#!/usr/bin/env bash
set -euo pipefail

# Run OVBuddy on macOS using the PIL-backed simulator backend:
# - Writes a single PNG frame (overwritten each update)
# - Optionally shows a live window (Tkinter) that updates each frame
#
# Usage:
#   ./scripts/run-macos-sim.sh
#   ./scripts/run-macos-sim.sh --test
#
# Env:
#   OVBUDDY_SIM_OUT=/path/to/frame.png   (default: dist/sim-output.png)
#   OVBUDDY_SIM_WINDOW=1                (default: 1)
#   OVBUDDY_SIM_SCALE=3                 (default: 3)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
PYTHON_BIN="${PYTHON_BIN:-python3}"

if ! command -v "${PYTHON_BIN}" >/dev/null 2>&1; then
  echo "ERROR: ${PYTHON_BIN} not found. Install Python 3 and try again." >&2
  exit 1
fi

export PYTHONUNBUFFERED=1
export TEST_MODE=1
export OVBUDDY_OUTPUT=sim
# Default: disable window on macOS (Tkinter can crash on some macOS versions)
# Set OVBUDDY_SIM_WINDOW=1 to enable (may fail on some systems)
export OVBUDDY_SIM_WINDOW="${OVBUDDY_SIM_WINDOW:-0}"
export OVBUDDY_SIM_SCALE="${OVBUDDY_SIM_SCALE:-3}"

cd "${DIST_DIR}"

# Default: don't start the web server on macOS.
DEFAULT_ARGS=(--no-web)

exec "${PYTHON_BIN}" ./ovbuddy.py "${DEFAULT_ARGS[@]}" "$@"
