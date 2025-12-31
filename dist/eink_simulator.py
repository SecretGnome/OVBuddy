#!/usr/bin/env python3
"""
Standalone eInk display simulator viewer.

OVBuddy's `OVBUDDY_OUTPUT=sim` backend writes frames to a PNG file.
This script watches that PNG and shows it in a scaled Tk window.

Configurable:
- width/height: logical display pixels (used for placeholder frame + window size hints)
- pixelDensity: integer scale factor for on-screen preview (crisp nearest-neighbor)
"""

from __future__ import annotations

import argparse
import http.server
import os
import socketserver
import sys
import time
import webbrowser
from dataclasses import dataclass
from typing import Callable
from typing import Optional, Tuple


def _env_int(name: str, default: int) -> int:
    try:
        raw = os.getenv(name, "")
        if raw is None:
            return default
        raw = str(raw).strip()
        if not raw:
            return default
        return int(raw)
    except Exception:
        return default


@dataclass(frozen=True)
class SimConfig:
    input_path: str
    width: int
    height: int
    pixel_density: int
    poll_interval_s: float
    mode: str
    http_port: int
    open_browser: bool


def _default_input_path() -> str:
    # default: dist/sim-output.png (relative to this file)
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.join(here, "sim-output.png")


def _load_image(path: str, fallback_size: Tuple[int, int]):
    from PIL import Image  # type: ignore

    if not os.path.exists(path):
        # placeholder: white frame (1-bit)
        return Image.new("1", fallback_size, 1)
    img = Image.open(path)
    # ensure loaded (Image.open is lazy)
    img.load()
    # normalize modes to something Tk likes
    if img.mode not in ("1", "L", "RGB"):
        img = img.convert("RGB")
    return img


class SimulatorViewer:
    def __init__(self, cfg: SimConfig):
        self.cfg = cfg
        self._last_sig: Optional[Tuple[float, int]] = None  # (mtime, size)

        try:
            import tkinter as tk  # type: ignore
            from PIL import ImageTk  # type: ignore
        except Exception as e:
            raise RuntimeError(
                f"Tkinter/PIL ImageTk not available: {e}\n"
                "On macOS: ensure you have a Python build with Tk support."
            ) from e

        self._tk = tk
        self._ImageTk = ImageTk

        self._root = tk.Tk()
        self._root.title("OVBuddy – eInk Simulator")
        self._root.resizable(False, False)
        self._label = tk.Label(self._root)
        self._label.pack()

        self._photo = None  # keep a ref alive

    def _file_signature(self) -> Optional[Tuple[float, int]]:
        try:
            st = os.stat(self.cfg.input_path)
            return (float(st.st_mtime), int(st.st_size))
        except Exception:
            return None

    def _render_once(self) -> None:
        from PIL import Image  # type: ignore

        sig = self._file_signature()
        if sig is not None and sig == self._last_sig:
            return
        self._last_sig = sig

        img = _load_image(self.cfg.input_path, (self.cfg.width, self.cfg.height))
        show = img
        if self.cfg.pixel_density and self.cfg.pixel_density != 1:
            try:
                show = img.resize(
                    (img.size[0] * self.cfg.pixel_density, img.size[1] * self.cfg.pixel_density),
                    resample=Image.NEAREST,
                )
            except Exception:
                show = img.resize((img.size[0] * self.cfg.pixel_density, img.size[1] * self.cfg.pixel_density))

        self._photo = self._ImageTk.PhotoImage(show)
        self._label.configure(image=self._photo)

    def _tick(self) -> None:
        try:
            self._render_once()
        except Exception as e:
            # Don't crash the window; show last frame and keep polling.
            sys.stderr.write(f"[sim-viewer] render error: {e}\n")
            sys.stderr.flush()
        self._root.after(int(self.cfg.poll_interval_s * 1000), self._tick)

    def run(self) -> None:
        # initial draw
        self._tick()
        self._root.mainloop()


class _QuietHandler(http.server.SimpleHTTPRequestHandler):
    # Reduce noisy logging
    def log_message(self, format, *args):  # noqa: A002 (shadow built-in)
        return


def _run_http_viewer(cfg: SimConfig) -> None:
    """Serve a tiny HTML page that auto-refreshes the PNG in a browser."""
    input_abs = os.path.abspath(cfg.input_path)
    root_dir = os.path.dirname(input_abs)
    file_name = os.path.basename(input_abs)

    # Determine display type from dimensions
    display_type = "lcd" if cfg.width == 128 and cfg.height == 128 else "eink"
    
    html = f"""<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>OVBuddy – Display Simulator</title>
    <style>
      body {{ font-family: system-ui, -apple-system, sans-serif; margin: 16px; }}
      .frame {{ border: 1px solid #ddd; display: inline-block; padding: 8px; }}
      .controls {{ display: flex; gap: 10px; align-items: center; margin: 10px 0 12px; flex-wrap: wrap; }}
      .controls label {{ font-size: 13px; color: #333; }}
      .controls .val {{ font-variant-numeric: tabular-nums; min-width: 22px; display: inline-block; text-align: right; }}
      .controls button {{ padding: 4px 10px; }}
      .controls select {{ padding: 4px 8px; font-size: 13px; }}
      .control-group {{ display: flex; gap: 10px; align-items: center; }}
      img {{
        image-rendering: pixelated;
        image-rendering: crisp-edges;
        width: {cfg.width * cfg.pixel_density}px;
        height: {cfg.height * cfg.pixel_density}px;
        background: #fff;
      }}
      .meta {{ color: #666; margin-top: 8px; font-size: 13px; }}
      code {{ background: #f5f5f5; padding: 2px 4px; border-radius: 4px; }}
      .info-box {{ background: #fff3cd; border: 1px solid #ffc107; border-radius: 4px; padding: 8px; margin-top: 8px; font-size: 12px; color: #856404; }}
    </style>
  </head>
  <body>
    <h3>OVBuddy – Display Simulator</h3>
    <div class="controls">
      <div class="control-group">
        <label>
          Display Type:
        </label>
        <select id="displayType">
          <option value="eink" {"selected" if display_type == "eink" else ""}>eInk (250×122)</option>
          <option value="lcd" {"selected" if display_type == "lcd" else ""}>LCD (128×128)</option>
        </select>
      </div>
      <div class="control-group">
        <label>
          pixelDensity:
          <span class="val" id="pdVal">{cfg.pixel_density}</span>
        </label>
        <button id="pdDec" type="button">-</button>
        <input id="pd" type="range" min="1" max="10" step="1" value="{cfg.pixel_density}" />
        <button id="pdInc" type="button">+</button>
        <span style="color:#666;font-size:12px;">(persists locally)</span>
      </div>
    </div>
    <div id="displayTypeInfo" class="info-box" style="display: none;">
      Display type changed. Restart the simulator with: <code>OVBUDDY_SIM_DISPLAY_TYPE=lcd ./scripts/run-macos-sim.sh</code> (or <code>eink</code> for eInk)
    </div>
    <div class="frame">
      <img id="img" alt="frame" src="{file_name}?t=0" />
    </div>
    <div class="meta">
      Watching <code>{file_name}</code> (poll {cfg.poll_interval_s:.2f}s) — size {cfg.width}×{cfg.height}, pixelDensity=<span id="pdMeta">{cfg.pixel_density}</span>
    </div>
    <script>
      const img = document.getElementById("img");
      const slider = document.getElementById("pd");
      const pdVal = document.getElementById("pdVal");
      const pdMeta = document.getElementById("pdMeta");
      const btnDec = document.getElementById("pdDec");
      const btnInc = document.getElementById("pdInc");
      const displayTypeSelect = document.getElementById("displayType");
      const displayTypeInfo = document.getElementById("displayTypeInfo");
      const baseW = {cfg.width};
      const baseH = {cfg.height};
      const storageKey = "ovbuddy_sim_pixelDensity";
      const displayTypeKey = "ovbuddy_sim_displayType";

      // Display type dimensions
      const displayDimensions = {{
        eink: {{ width: 250, height: 122 }},
        lcd: {{ width: 128, height: 128 }}
      }};

      function clamp(n, lo, hi) {{
        return Math.max(lo, Math.min(hi, n));
      }}

      function applyPD(pd) {{
        pd = clamp(parseInt(pd, 10) || 1, 1, 10);
        slider.value = String(pd);
        pdVal.textContent = String(pd);
        pdMeta.textContent = String(pd);
        const displayType = displayTypeSelect.value;
        const dims = displayDimensions[displayType] || displayDimensions.eink;
        img.style.width = String(dims.width * pd) + "px";
        img.style.height = String(dims.height * pd) + "px";
        try {{ localStorage.setItem(storageKey, String(pd)); }} catch (e) {{}}
      }}

      function updateDisplayType() {{
        const displayType = displayTypeSelect.value;
        const dims = displayDimensions[displayType] || displayDimensions.eink;
        const currentDims = {{ width: baseW, height: baseH }};
        
        // Show info if dimensions don't match
        if (dims.width !== currentDims.width || dims.height !== currentDims.height) {{
          displayTypeInfo.style.display = "block";
        }} else {{
          displayTypeInfo.style.display = "none";
        }}
        
        // Update image size
        applyPD(parseInt(slider.value, 10) || 1);
        
        // Save to localStorage
        try {{ localStorage.setItem(displayTypeKey, displayType); }} catch (e) {{}}
      }}

      // Initialize from localStorage if present
      try {{
        const saved = localStorage.getItem(storageKey);
        if (saved) applyPD(saved);
        else applyPD(slider.value);
        
        const savedDisplayType = localStorage.getItem(displayTypeKey);
        if (savedDisplayType && (savedDisplayType === "eink" || savedDisplayType === "lcd")) {{
          displayTypeSelect.value = savedDisplayType;
          updateDisplayType();
        }}
      }} catch (e) {{
        applyPD(slider.value);
      }}

      slider.addEventListener("input", (e) => applyPD(e.target.value));
      btnDec.addEventListener("click", () => applyPD((parseInt(slider.value, 10) || 1) - 1));
      btnInc.addEventListener("click", () => applyPD((parseInt(slider.value, 10) || 1) + 1));
      displayTypeSelect.addEventListener("change", updateDisplayType);

      // Keyboard shortcuts: +/- adjust
      window.addEventListener("keydown", (e) => {{
        if (e.key === "+" || e.key === "=") btnInc.click();
        if (e.key === "-" || e.key === "_") btnDec.click();
      }});

      function tick() {{
        img.src = "{file_name}?t=" + Date.now();
      }}
      setInterval(tick, {int(cfg.poll_interval_s * 1000)});
    </script>
  </body>
</html>
"""

    class Handler(_QuietHandler):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, directory=root_dir, **kwargs)

        def do_GET(self):  # noqa: N802 (stdlib naming)
            if self.path in ("/", "/index.html"):
                data = html.encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
                return
            return super().do_GET()

    # Try to bind to the requested port, or find an available port
    port = cfg.http_port
    max_attempts = 10
    httpd = None
    
    for attempt in range(max_attempts):
        try:
            httpd = socketserver.TCPServer(("127.0.0.1", port), Handler)
            break
        except OSError as e:
            if e.errno == 48:  # Address already in use
                if attempt < max_attempts - 1:
                    port += 1
                    continue
                else:
                    sys.stderr.write(
                        f"[sim-viewer] Error: Could not find available port "
                        f"(tried {cfg.http_port}-{port}). "
                        f"Port {cfg.http_port} is already in use.\n"
                        f"  Kill existing process: lsof -ti:{cfg.http_port} | xargs kill\n"
                        f"  Or use a different port: OVBUDDY_SIM_HTTP_PORT={port+1} ...\n"
                    )
                    sys.stderr.flush()
                    raise
            else:
                raise
    
    if httpd is None:
        raise RuntimeError("Failed to create HTTP server")
    
    url = f"http://127.0.0.1:{port}/"
    if port != cfg.http_port:
        sys.stdout.write(f"[sim-viewer] Port {cfg.http_port} in use, using {port} instead\n")
    sys.stdout.write(f"[sim-viewer] http viewer: {url}\n")
    sys.stdout.flush()
    if cfg.open_browser:
        try:
            webbrowser.open(url)
        except Exception:
            pass
    httpd.serve_forever()


def parse_args(argv) -> SimConfig:
    p = argparse.ArgumentParser(description="OVBuddy eInk simulator viewer (watches a PNG and displays it).")
    p.add_argument("--input", dest="input_path", default=os.getenv("OVBUDDY_SIM_OUT") or _default_input_path())
    p.add_argument("--width", type=int, default=_env_int("OVBUDDY_SIM_WIDTH", 250))
    p.add_argument("--height", type=int, default=_env_int("OVBUDDY_SIM_HEIGHT", 122))
    p.add_argument(
        "--pixel-density",
        dest="pixel_density",
        type=int,
        default=_env_int("OVBUDDY_SIM_PIXEL_DENSITY", _env_int("OVBUDDY_SIM_SCALE", 3)),
        help="Integer preview scale factor (alias: OVBUDDY_SIM_PIXEL_DENSITY; legacy: OVBUDDY_SIM_SCALE).",
    )
    p.add_argument("--poll-interval", type=float, default=float(os.getenv("OVBUDDY_SIM_POLL", "0.2") or "0.2"))
    p.add_argument(
        "--mode",
        choices=("auto", "tk", "http"),
        default=(os.getenv("OVBUDDY_SIM_VIEWER_MODE") or ("http" if sys.platform == "darwin" else "auto")).strip().lower(),
        help="Viewer mode: tk (window), http (browser), auto (try tk then fall back to http).",
    )
    p.add_argument("--http-port", type=int, default=_env_int("OVBUDDY_SIM_HTTP_PORT", 8765))
    p.add_argument(
        "--no-open",
        dest="open_browser",
        action="store_false",
        default=(os.getenv("OVBUDDY_SIM_OPEN", "1") != "0"),
        help="Don't auto-open the browser in http mode.",
    )
    ns = p.parse_args(argv)

    w = int(ns.width)
    h = int(ns.height)
    pd = max(1, int(ns.pixel_density))
    if w <= 0 or h <= 0:
        raise SystemExit("ERROR: width/height must be positive integers")
    if ns.poll_interval <= 0:
        raise SystemExit("ERROR: poll-interval must be > 0")
    if int(ns.http_port) <= 0 or int(ns.http_port) > 65535:
        raise SystemExit("ERROR: http-port must be 1..65535")

    return SimConfig(
        input_path=str(ns.input_path),
        width=w,
        height=h,
        pixel_density=pd,
        poll_interval_s=float(ns.poll_interval),
        mode=str(ns.mode),
        http_port=int(ns.http_port),
        open_browser=bool(ns.open_browser),
    )


def main(argv=None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    cfg = parse_args(argv)
    sys.stdout.write(
        "[sim-viewer] watching: {p}\n[sim-viewer] size: {w}x{h}, pixelDensity={pd} (scale)\n".format(
            p=cfg.input_path, w=cfg.width, h=cfg.height, pd=cfg.pixel_density
        )
    )
    sys.stdout.flush()
    mode = (cfg.mode or "auto").strip().lower()
    # Safety: on macOS, Tk can abort the interpreter (not catchable) on some builds.
    # Treat "auto" as "http" to avoid hard crashes unless the user explicitly requests tk.
    if mode == "auto" and sys.platform == "darwin":
        mode = "http"
    if mode in ("auto", "tk"):
        try:
            viewer = SimulatorViewer(cfg)
            viewer.run()
            return 0
        except Exception as e:
            if mode == "tk":
                raise
            sys.stderr.write(f"[sim-viewer] tk viewer failed, falling back to http: {e}\n")
            sys.stderr.flush()

    _run_http_viewer(cfg)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())


