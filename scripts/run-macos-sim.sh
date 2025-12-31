#!/usr/bin/env bash
set -euo pipefail

# Run OVBuddy on macOS using the PNG simulator backend:
# - OVBuddy writes a single PNG frame (overwritten each refresh)
# - A separate viewer process (`dist/eink_simulator.py`) watches that PNG and shows it
#
# Usage:
#   ./scripts/run-macos-sim.sh
#   ./scripts/run-macos-sim.sh --test
#   ./scripts/run-macos-sim.sh --display-type lcd
#   ./scripts/run-macos-sim.sh --display-type eink
#
# Env:
#   OVBUDDY_SIM_OUT=/path/to/frame.png          (default: dist/sim-output.png)
#   OVBUDDY_SIM_DISPLAY_TYPE=eink|lcd           (default: eink, or from config.json)
#   OVBUDDY_SIM_WIDTH=250                       (default: auto based on display_type)
#   OVBUDDY_SIM_HEIGHT=122                      (default: auto based on display_type)
#   OVBUDDY_SIM_PIXEL_DENSITY=3                 (default: 3)  # viewer scale factor
#   OVBUDDY_SIM_VIEWER=1                        (default: 1)  # set 0 to disable viewer

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
export OVBUDDY_SIM_OUT="${OVBUDDY_SIM_OUT:-${DIST_DIR}/sim-output.png}"

# Parse command-line arguments for display type
DISPLAY_TYPE_ARG=""
ARGS=()
expect_display_type=false
for arg in "$@"; do
    if [[ "$expect_display_type" == "true" ]]; then
        DISPLAY_TYPE_ARG="$arg"
        expect_display_type=false
        continue
    fi
    case "$arg" in
        --display-type=*)
            DISPLAY_TYPE_ARG="${arg#*=}"
            ;;
        --display-type)
            expect_display_type=true
            ;;
        *)
            ARGS+=("$arg")
            ;;
    esac
done

# Determine display type: from arg, env var, or config file
if [[ -n "$DISPLAY_TYPE_ARG" ]]; then
    export OVBUDDY_SIM_DISPLAY_TYPE="$DISPLAY_TYPE_ARG"
elif [[ -z "${OVBUDDY_SIM_DISPLAY_TYPE:-}" ]]; then
    # Try to read from config.json
    CONFIG_FILE="${DIST_DIR}/config.json"
    if [[ -f "$CONFIG_FILE" ]]; then
        DISPLAY_TYPE_FROM_CONFIG=$(grep -o '"display_type"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" 2>/dev/null | grep -o '"[^"]*"' | tail -1 | tr -d '"' || echo "")
        if [[ -n "$DISPLAY_TYPE_FROM_CONFIG" ]]; then
            export OVBUDDY_SIM_DISPLAY_TYPE="$DISPLAY_TYPE_FROM_CONFIG"
        fi
    fi
fi

# Set dimensions based on display type (can be overridden by env vars)
if [[ -z "${OVBUDDY_SIM_WIDTH:-}" ]]; then
    if [[ "${OVBUDDY_SIM_DISPLAY_TYPE:-eink}" == "lcd" ]]; then
        export OVBUDDY_SIM_WIDTH=128
        export OVBUDDY_SIM_HEIGHT=128
    else
        export OVBUDDY_SIM_WIDTH=250
        export OVBUDDY_SIM_HEIGHT=122
    fi
elif [[ -z "${OVBUDDY_SIM_HEIGHT:-}" ]]; then
    # If width is set but height isn't, set height based on display type
    if [[ "${OVBUDDY_SIM_DISPLAY_TYPE:-eink}" == "lcd" ]]; then
        export OVBUDDY_SIM_HEIGHT=128
    else
        export OVBUDDY_SIM_HEIGHT=122
    fi
fi

export OVBUDDY_SIM_PIXEL_DENSITY="${OVBUDDY_SIM_PIXEL_DENSITY:-${OVBUDDY_SIM_SCALE:-3}}"
export OVBUDDY_SIM_VIEWER="${OVBUDDY_SIM_VIEWER:-1}"
# Tk often hard-crashes Python on some macOS + system-Python builds.
# Default to the HTTP (browser) viewer on macOS unless explicitly overridden.
if [[ -z "${OVBUDDY_SIM_VIEWER_MODE+x}" ]]; then
  if [[ "$(uname -s)" == "Darwin" ]]; then
    export OVBUDDY_SIM_VIEWER_MODE="http"
  else
    export OVBUDDY_SIM_VIEWER_MODE="auto"
  fi
else
  export OVBUDDY_SIM_VIEWER_MODE="${OVBUDDY_SIM_VIEWER_MODE}"
fi

cd "${DIST_DIR}"

# Default: don't start the web server on macOS.
DEFAULT_ARGS=(--no-web)

VIEWER_PID=""
cleanup() {
  if [[ -n "${VIEWER_PID}" ]]; then
    kill "${VIEWER_PID}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

if [[ "${OVBUDDY_SIM_VIEWER}" == "1" ]]; then
  "${PYTHON_BIN}" ./eink_simulator.py \
    --input "${OVBUDDY_SIM_OUT}" \
    --width "${OVBUDDY_SIM_WIDTH}" \
    --height "${OVBUDDY_SIM_HEIGHT}" \
    --pixel-density "${OVBUDDY_SIM_PIXEL_DENSITY}" \
    --mode "${OVBUDDY_SIM_VIEWER_MODE}" &
  VIEWER_PID="$!"
fi

"${PYTHON_BIN}" ./ovbuddy.py "${DEFAULT_ARGS[@]}" ${ARGS[@]+"${ARGS[@]}"}
