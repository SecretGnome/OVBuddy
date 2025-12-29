#!/usr/bin/env bash
set -euo pipefail

# Run OVBuddy on macOS without e-ink hardware.
# - Uses TEST_MODE=1 to avoid importing Waveshare/RPi GPIO drivers
# - Enables an ANSI "screen" renderer in the terminal
#
# Usage:
#   ./scripts/run-macos.sh                # real API fetch (uses dist/config.json)
#   ./scripts/run-macos.sh --test         # mock departures
#   ./scripts/run-macos.sh --no-web       # (default) no Flask/Bonjour
#
# Notes:
# - Edit `dist/config.json` (or copy it) to change stations/lines.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
PYTHON_BIN="${PYTHON_BIN:-python3}"

if ! command -v "${PYTHON_BIN}" >/dev/null 2>&1; then
  echo "ERROR: ${PYTHON_BIN} not found. Install Python 3 and try again." >&2
  exit 1
fi

# Use the alt-screen buffer by default so the UI doesn't spam scrollback.
ALT_SCREEN="${OVBUDDY_ALT_SCREEN:-1}"

cleanup() {
  if [[ -t 1 ]]; then
    # reset attributes + show cursor
    printf '\033[0m\033[?25h' || true
    if [[ "${ALT_SCREEN}" == "1" ]]; then
      # leave alt-screen
      printf '\033[?1049l' || true
    fi
  fi
}
trap cleanup EXIT INT TERM

if [[ -t 1 && "${ALT_SCREEN}" == "1" ]]; then
  # enter alt-screen + clear
  printf '\033[?1049h\033[2J\033[H' || true
fi

export PYTHONUNBUFFERED=1
export TEST_MODE=1
export OVBUDDY_OUTPUT=terminal
export OVBUDDY_TERMINAL_UI=1

cd "${DIST_DIR}"

# Default: don't start the web server on macOS (avoids Flask/zeroconf deps).
DEFAULT_ARGS=(--no-web)

exec "${PYTHON_BIN}" ./ovbuddy.py "${DEFAULT_ARGS[@]}" "$@"
