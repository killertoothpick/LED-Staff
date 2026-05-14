#!/usr/bin/env bash
set -euo pipefail

cd "${1:-$(pwd)}"

if [[ ! -f main.py || ! -f config.py || ! -d hardware || ! -d ui ]]; then
  echo "Run this from the led_staff_v1 project root, or pass the project path as the first argument." >&2
  exit 1
fi

backup_dir="backups/top_ui_controls_patch_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$backup_dir"
for f in \
  main.py config.py core/debug.py hardware/leds.py hardware/audio.py hardware/imu.py \
  animations/sparkle.py tools/test_top_only.py; do
  [[ -f "$f" ]] && cp -a "$f" "$backup_dir/$(basename "$f")"
done

echo "Backed up touched files to $backup_dir"

python - <<'PY'
from pathlib import Path
import re

p = Path('config.py')
text = p.read_text()

# The top is now addressed as 7 logical LEDs. The two physical top strands are
# mirrored/paired in hardware, so logical LED 3 appears on both right and left.
text = re.sub(r'^TOP_COUNT\s*=\s*\d+\s*$', 'TOP_COUNT = 7', text, flags=re.M)

if 'TOP_LOGICAL_COUNT' not in text:
    marker = 'TOP_COUNT = 7\n'
    insert = '''\n# Top geometry, revised after hardware bring-up. The top is two mirrored\n# physical strands of 7 LEDs. Software sends 7 logical pixels; each logical\n# index lights the same-numbered LED on both strands.\nTOP_LOGICAL_COUNT = 7\nTOP_TRIANGLE_SHARED_COUNT = 2  # first 2 mirrored LEDs form the shared triangle side\nTOP_TRIANGLE_BRANCH_COUNT = 5  # remaining 5 mirrored LEDs form the other two sides\n'''
    if marker not in text:
        raise SystemExit('Could not find TOP_COUNT line in config.py')
    text = text.replace(marker, marker + insert)
else:
    text = re.sub(r'^TOP_LOGICAL_COUNT\s*=.*$', 'TOP_LOGICAL_COUNT = 7', text, flags=re.M)
    text = re.sub(r'^TOP_TRIANGLE_SHARED_COUNT\s*=.*$', 'TOP_TRIANGLE_SHARED_COUNT = 2', text, flags=re.M)
    text = re.sub(r'^TOP_TRIANGLE_BRANCH_COUNT\s*=.*$', 'TOP_TRIANGLE_BRANCH_COUNT = 5', text, flags=re.M)

# Keep / create the debug dashboard settings.
if 'DEBUG_CONSOLE' not in text:
    text += '''\n# Live terminal dashboard. Enabled by default when run manually in a terminal.\n# Use LED_STAFF_DEBUG=0 to go back to plain logs.\nDEBUG_CONSOLE = os.environ.get("LED_STAFF_DEBUG", "1") != "0"\nDEBUG_CONSOLE_HZ = float(os.environ.get("LED_STAFF_DEBUG_HZ", "4"))\nDEBUG_LOG_LINES = int(os.environ.get("LED_STAFF_DEBUG_LOG_LINES", "8"))\n'''
else:
    if 'DEBUG_CONSOLE_HZ' not in text:
        text += '\nDEBUG_CONSOLE_HZ = float(os.environ.get("LED_STAFF_DEBUG_HZ", "4"))\n'
    if 'DEBUG_LOG_LINES' not in text:
        text += '\nDEBUG_LOG_LINES = int(os.environ.get("LED_STAFF_DEBUG_LOG_LINES", "8"))\n'

# Keep / create logical control-circle dial settings.
if 'CONTROL_DIAL_ZERO' not in text:
    marker = 'CONTROL_COUNT = CONTROL_END - CONTROL_START + 1\n'
    insert = '''\n# Logical direction for the 16-LED control circle while using it as a dial.\n# Increase moves clockwise; decrease moves counter-clockwise. If the physical\n# ring ever appears reversed, flip CONTROL_DIAL_CLOCKWISE between 1 and -1.\nCONTROL_DIAL_ZERO = 0\nCONTROL_DIAL_CLOCKWISE = -1\n'''
    if marker in text:
        text = text.replace(marker, marker + insert)
else:
    text = re.sub(r'^CONTROL_DIAL_ZERO\s*=.*$', 'CONTROL_DIAL_ZERO = 0', text, flags=re.M)
    text = re.sub(r'^CONTROL_DIAL_CLOCKWISE\s*=.*$', 'CONTROL_DIAL_CLOCKWISE = -1', text, flags=re.M)

if 'IMU_AXIS_X' not in text:
    text += '''\n# IMU axis convention confirmed on hardware. Values are passed through raw,\n# but this documents how to interpret them in animations/debug output.\nIMU_AXIS_X = "right"\nIMU_AXIS_Y = "up"\nIMU_AXIS_Z = "perpendicular"\n'''

p.write_text(text)
PY

cat > core/debug.py <<'PY'
from __future__ import annotations

import sys
import time
from collections import deque

import config
from animations.base import Animation
from core.presets import PresetStore
from core.settings import BRIGHTNESS_OPTIONS, GAIN_OPTIONS, SPEED_OPTIONS, Settings
from ui.menu import UIState


class RuntimeLog:
    """Small in-memory log for the live console dashboard."""

    def __init__(self, max_lines: int | None = None) -> None:
        self.max_lines = int(max_lines or config.DEBUG_LOG_LINES)
        self._lines: deque[str] = deque(maxlen=self.max_lines)

    def add(self, message: str) -> None:
        stamp = time.strftime("%H:%M:%S")
        line = f"{stamp} {message}"
        self._lines.append(line)
        if not sys.stdout.isatty():
            print(line, flush=True)

    def snapshot(self) -> list[str]:
        return list(self._lines)


class DebugDashboard:
    def __init__(self, hz: float | None = None) -> None:
        safe_hz = max(0.5, float(hz or config.DEBUG_CONSOLE_HZ))
        self.interval = 1.0 / safe_hz
        self._next_render_at = 0.0
        self._last_fps: float | None = None

    @property
    def enabled(self) -> bool:
        return bool(config.DEBUG_CONSOLE) and sys.stdout.isatty()

    def render(
        self,
        *,
        now: float,
        frame: int,
        fps_report: float | None,
        ui: UIState,
        pages,
        animations: list[Animation],
        active_settings: Settings,
        pending_settings: Settings,
        imu_state,
        audio_state,
        beat_state,
        log: RuntimeLog,
        presets: PresetStore | None = None,
    ) -> None:
        if fps_report is not None:
            self._last_fps = fps_report
        if not self.enabled or now < self._next_render_at:
            return
        self._next_render_at = now + self.interval

        mode = "SETTINGS" if ui.in_settings else "RUN"
        active_animation = animations[active_settings.animation_index % len(animations)].name if animations else "none"
        pending_animation = animations[pending_settings.animation_index % len(animations)].name if animations else "none"
        preset_text = f"{ui.preset_slot + 1}/{config.PRESET_SLOTS}"

        lines: list[str] = []
        lines.append("LED STAFF DEBUG  |  Ctrl+C exits  |  LED_STAFF_DEBUG=0 disables this screen")
        lines.append("=" * 82)
        lines.append(f"Mode: {mode:<9} Frame: {frame:<8} FPS: {self._fmt(self._last_fps, 1):>6}   Preset: {preset_text}")
        lines.append(f"Beat: bpm={beat_state.bpm_smooth:6.1f} raw={beat_state.bpm:6.1f} phase={beat_state.phase:4.2f} confidence={beat_state.confidence:4.2f} just_beat={beat_state.just_beat}")
        lines.append(f"Audio: vol={audio_state.volume:5.3f} smooth={audio_state.volume_smooth:5.3f} bass={audio_state.bass:5.3f} mids={audio_state.mids:5.3f} treble={audio_state.treble:5.3f} clipped={audio_state.clipped}")
        lines.append(f"IMU axes: x=right y=up z=perpendicular | available={imu_state.available} motion={imu_state.motion:5.2f} accel=({imu_state.ax:5.2f}, {imu_state.ay:5.2f}, {imu_state.az:5.2f})")
        lines.append(f"IMU tilt: tilt_x={imu_state.tilt_x:6.2f} tilt_y={imu_state.tilt_y:6.2f} tilt_angle={imu_state.tilt_angle:6.2f}")
        lines.append("")
        lines.append("Active settings")
        lines.append(f"  Animation : {active_animation}")
        lines.append(f"  Palette   : {active_settings.palette.name}")
        lines.append(f"  Speed     : {active_settings.speed.name}")
        lines.append(f"  Brightness: {active_settings.brightness:.2f}  index {active_settings.brightness_index + 1}/{len(BRIGHTNESS_OPTIONS)}")
        lines.append(f"  Gain      : {active_settings.gain:.2f}  index {active_settings.gain_index + 1}/{len(GAIN_OPTIONS)}")

        if ui.in_settings:
            page = pages[ui.page_index]
            value = menu_value_text(page.name, pending_settings, ui, animations, pages, presets)
            lines.append("")
            lines.append("Current menu")
            lines.append(f"  Page      : {ui.page_index + 1}/{len(pages)}  {page.name}")
            lines.append(f"  Value     : {value}")
            lines.append(f"  Pending animation: {pending_animation}")
            lines.append("  Controls  : TL/TR change page, BL/BR change value")
            lines.append("              TL = previous page, TR = next page")
            lines.append("              BL = value down/counter-clockwise, BR = value up/clockwise")
            lines.append("              BC tap = apply, BC hold = cancel")
        else:
            lines.append("")
            lines.append("Run controls")
            lines.append("  BC tap enters settings")
            lines.append("  TL/TR cycle saved presets")
            lines.append("  BL/BR animation hotkeys: previous/next animation")

        lines.append("")
        lines.append("Top geometry")
        lines.append(f"  Logical top LEDs: {config.TOP_COUNT}; two physical 7-LED strands mirror each logical index")
        lines.append(f"  First {config.TOP_TRIANGLE_SHARED_COUNT} mirrored LEDs = shared side; remaining {config.TOP_TRIANGLE_BRANCH_COUNT} = branch sides")

        lines.append("")
        lines.append("Recent log")
        recent = log.snapshot()
        if recent:
            lines.extend(f"  {item}" for item in recent[-config.DEBUG_LOG_LINES:])
        else:
            lines.append("  <no log lines yet>")

        sys.stdout.write("\033[2J\033[H" + "\n".join(lines) + "\n")
        sys.stdout.flush()

    @staticmethod
    def _fmt(value: float | None, places: int = 1) -> str:
        if value is None:
            return "--"
        return f"{value:.{places}f}"


def menu_value_text(
    page_name: str,
    settings: Settings,
    ui: UIState,
    animations: list[Animation],
    pages=None,
    presets: PresetStore | None = None,
) -> str:
    name = page_name.lower()
    if name == "animation":
        if not animations:
            return "none"
        return f"{settings.animation_index + 1}/{len(animations)} {animations[settings.animation_index % len(animations)].name}"
    if name == "palette":
        return f"{settings.palette_index + 1} {settings.palette.name}"
    if name == "speed":
        return f"{settings.speed_index + 1}/{len(SPEED_OPTIONS)} {settings.speed.name}"
    if name == "brightness":
        return f"{settings.brightness_index + 1}/{len(BRIGHTNESS_OPTIONS)} {settings.brightness:.2f}"
    if name == "gain":
        return f"{settings.gain_index + 1}/{len(GAIN_OPTIONS)} {settings.gain:.2f}"
    if name == "save":
        return f"Preset slot {ui.preset_slot + 1}/{config.PRESET_SLOTS}"
    if name == "load":
        loaded = ""
        if presets is not None:
            s = presets.get(ui.preset_slot)
            loaded_anim = animations[s.animation_index % len(animations)].name if animations else str(s.animation_index + 1)
            loaded = f" anim={loaded_anim} palette={s.palette.name} speed={s.speed.name}"
        return f"Preset slot {ui.preset_slot + 1}/{config.PRESET_SLOTS}{loaded}"
    return ""
PY

cat > hardware/audio.py <<'PY'
from __future__ import annotations

import threading
import time
from collections.abc import Callable

import config
from core.context import AudioState


class AudioProcessor:
    """Optional live audio state."""

    def __init__(self, logger: Callable[[str], None] | None = None) -> None:
        self._logger = logger or print
        self._lock = threading.Lock()
        self._state = AudioState()
        self._thread: threading.Thread | None = None
        self._running = False
        self._enabled = config.ENABLE_AUDIO and not config.MOCK_HARDWARE

    def start(self) -> None:
        if not self._enabled:
            self._logger("Audio disabled; using silent audio state")
            return
        self._running = True
        self._thread = threading.Thread(target=self._run, name="audio", daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._running = False
        if self._thread:
            self._thread.join(timeout=1.0)

    def snapshot(self, gain: float = 1.0) -> AudioState:
        with self._lock:
            s = AudioState(**self._state.__dict__)
        s.gain = gain
        s.volume = min(1.0, s.volume * gain)
        s.volume_smooth = min(1.0, s.volume_smooth * gain)
        s.bass = min(1.0, s.bass * gain)
        s.mids = min(1.0, s.mids * gain)
        s.treble = min(1.0, s.treble * gain)
        return s

    def _run(self) -> None:
        try:
            import numpy as np
            import sounddevice as sd
        except Exception as exc:
            self._logger(f"Audio imports failed; continuing without audio: {exc}")
            return

        def callback(indata, frames, time_info, status):
            try:
                samples = np.asarray(indata[:, 0], dtype=np.float32)
                rms = float(np.sqrt(np.mean(samples * samples)))
                clipped = bool(np.max(np.abs(samples)) > 0.98)
                volume = min(1.0, rms * 12.0)
                with self._lock:
                    prev = self._state.volume_smooth
                    smooth = prev * 0.85 + volume * 0.15
                    self._state = AudioState(
                        volume=volume,
                        volume_smooth=smooth,
                        bass=volume,
                        mids=volume,
                        treble=volume,
                        gain=1.0,
                        clipped=clipped,
                    )
            except Exception:
                pass

        while self._running:
            try:
                with sd.InputStream(
                    channels=1,
                    samplerate=config.AUDIO_SAMPLE_RATE,
                    blocksize=config.AUDIO_BLOCK_SIZE,
                    callback=callback,
                ):
                    self._logger("Audio input initialized")
                    while self._running:
                        time.sleep(0.25)
            except Exception as exc:
                self._logger(f"Audio input unavailable, retrying: {exc}")
                time.sleep(2.0)
PY

cat > hardware/imu.py <<'PY'
from __future__ import annotations

import math
from collections.abc import Callable

import config
from core.context import IMUState


class IMUReader:
    """Read IMU values using the project axis convention.

    Confirmed physical convention:
      x = right
      y = up
      z = perpendicular / the remaining axis
    """

    def __init__(self, logger: Callable[[str], None] | None = None) -> None:
        self._logger = logger or print
        self.sensor = None
        self.available = False
        self.last = IMUState()
        if not config.MOCK_HARDWARE:
            self._init_sensor()

    def _init_sensor(self) -> None:
        try:
            import board
            from adafruit_lsm6ds.lsm6dsox import LSM6DSOX

            i2c = board.I2C()
            self.sensor = LSM6DSOX(i2c)
            self.available = True
            self._logger("IMU initialized; axes: x=right y=up z=perpendicular")
        except Exception as exc:
            self.sensor = None
            self.available = False
            self._logger(f"IMU unavailable, continuing without it: {exc}")

    def update(self) -> IMUState:
        if not self.available or self.sensor is None:
            self.last = IMUState(available=False)
            return self.last
        try:
            # Raw sensor axes, interpreted as x=right, y=up, z=perpendicular.
            ax, ay, az = self.sensor.acceleration
            motion = math.sqrt(ax * ax + ay * ay + az * az)
            tilt_x = math.atan2(ax, math.sqrt(ay * ay + az * az))
            tilt_y = math.atan2(ay, math.sqrt(ax * ax + az * az))
            tilt_angle = math.atan2(ay, ax)
            gx = gy = gz = 0.0
            try:
                gx, gy, gz = self.sensor.gyro
            except Exception:
                pass
            self.last = IMUState(
                ax=ax,
                ay=ay,
                az=az,
                gx=gx,
                gy=gy,
                gz=gz,
                motion=motion,
                tilt_x=tilt_x,
                tilt_y=tilt_y,
                tilt_angle=tilt_angle,
                available=True,
            )
        except Exception as exc:
            self._logger(f"IMU read failed: {exc}")
            self.available = False
            self.last = IMUState(available=False)
        return self.last

    def snapshot(self) -> IMUState:
        return self.last
PY

cat > hardware/leds.py <<'PY'
from __future__ import annotations

from typing import Iterable

import config
from core.colors import BLACK, Color, scale_color


class MockNeoPixel:
    def __init__(self, pin, n: int, brightness: float = 1.0, auto_write: bool = False, pixel_order=None):
        self.pin = pin
        self.n = n
        self.brightness = brightness
        self.auto_write = auto_write
        self.pixel_order = pixel_order
        self.buf = [BLACK for _ in range(n)]

    def __len__(self) -> int:
        return self.n

    def __setitem__(self, index: int, color: Color) -> None:
        if 0 <= index < self.n:
            self.buf[index] = color

    def __getitem__(self, index: int) -> Color:
        return self.buf[index]

    def fill(self, color: Color) -> None:
        self.buf = [color for _ in range(self.n)]

    def show(self) -> None:
        pass


class StaffSurface:
    """Logical drawing surface for the LED staff.

    The top now has 7 logical LEDs. The two physical 7-LED top strands mirror
    the same data, so setting top logical LED 3 lights LED 3 on both strands.
    """

    def __init__(self, main_pixels, top_pixels):
        self.main = main_pixels
        self.top = top_pixels
        self.output_scale = 1.0
        self._main_pending = [BLACK for _ in range(config.MAIN_COUNT)]
        self._top_pending = [BLACK for _ in range(config.TOP_COUNT)]

        self.right_down = list(range(config.SHAFT_RIGHT_START, config.SHAFT_RIGHT_END + 1))
        self.left_up = list(range(config.SHAFT_LEFT_START, config.SHAFT_LEFT_END + 1))
        self.left_down = list(reversed(self.left_up))

    @classmethod
    def create(cls) -> "StaffSurface":
        if config.MOCK_HARDWARE:
            return cls(MockNeoPixel(config.MAIN_PIXEL_PIN, config.MAIN_COUNT), MockNeoPixel(config.TOP_PIXEL_PIN, config.TOP_COUNT))

        import board
        import neopixel

        main_pin = getattr(board, config.MAIN_PIXEL_PIN)
        top_pin = getattr(board, config.TOP_PIXEL_PIN)

        main = neopixel.NeoPixel(
            main_pin,
            config.MAIN_COUNT,
            brightness=config.DEFAULT_MAIN_BRIGHTNESS,
            auto_write=False,
            pixel_order=neopixel.GRB,
        )
        top = neopixel.NeoPixel(
            top_pin,
            config.TOP_COUNT,
            brightness=config.DEFAULT_TOP_BRIGHTNESS,
            auto_write=False,
            pixel_order=neopixel.RGB,
        )
        return cls(main, top)

    def set_output_scale(self, scale: float) -> None:
        self.output_scale = max(0.0, min(config.MAX_OUTPUT_SCALE, scale))

    def clear(self) -> None:
        self._main_pending = [BLACK for _ in range(config.MAIN_COUNT)]
        self._top_pending = [BLACK for _ in range(config.TOP_COUNT)]

    def fill_all(self, color: Color) -> None:
        self.fill_top(color)
        self.fill_control(color)
        self.fill_shaft(color)

    def set_main_raw(self, index: int, color: Color) -> None:
        if 0 <= index < config.MAIN_COUNT:
            self._main_pending[index] = color

    def set_top_pixel(self, index: int, color: Color) -> None:
        """Set one logical top LED.

        Hardware mirrors each logical top LED onto both physical top strands.
        """
        if 0 <= index < config.TOP_COUNT:
            self._top_pending[index] = color

    def fill_top(self, color: Color) -> None:
        for i in range(config.TOP_COUNT):
            self._top_pending[i] = color

    def fill_top_shared_side(self, color: Color) -> None:
        for i in range(min(config.TOP_TRIANGLE_SHARED_COUNT, config.TOP_COUNT)):
            self.set_top_pixel(i, color)

    def fill_top_branch_sides(self, color: Color) -> None:
        for i in range(config.TOP_TRIANGLE_SHARED_COUNT, config.TOP_COUNT):
            self.set_top_pixel(i, color)

    def set_control(self, index: int, color: Color) -> None:
        if 0 <= index < config.CONTROL_COUNT:
            self._main_pending[config.CONTROL_START + index] = color

    def control_dial_index(self, step: int | float) -> int:
        """Map logical clockwise dial steps to the physical control-ring index."""
        step_i = int(round(step))
        return (config.CONTROL_DIAL_ZERO + config.CONTROL_DIAL_CLOCKWISE * step_i) % config.CONTROL_COUNT

    def set_control_dial(self, step: int | float, color: Color) -> None:
        self.set_control(self.control_dial_index(step), color)

    def fill_control(self, color: Color) -> None:
        for i in range(config.CONTROL_COUNT):
            self.set_control(i, color)

    def set_control_ring(self, colors: Iterable[Color]) -> None:
        for i, color in enumerate(colors):
            if i >= config.CONTROL_COUNT:
                break
            self.set_control(i, color)

    def fill_shaft(self, color: Color) -> None:
        for idx in self.right_down:
            self._main_pending[idx] = color
        for idx in self.left_up:
            self._main_pending[idx] = color

    def set_shaft_depth(self, depth: int | float, color: Color) -> None:
        """Set both shaft sides at a visual top-to-bottom depth."""
        depth_i = int(round(depth))
        if not (0 <= depth_i < config.SHAFT_DEPTH):
            return
        ri = self._scaled_index(depth_i, config.SHAFT_DEPTH, len(self.right_down))
        li = self._scaled_index(depth_i, config.SHAFT_DEPTH, len(self.left_down))
        self._main_pending[self.right_down[ri]] = color
        self._main_pending[self.left_down[li]] = color

    def set_shaft_side_depth(self, side: str, depth: int | float, color: Color) -> None:
        depth_i = int(round(depth))
        if not (0 <= depth_i < config.SHAFT_DEPTH):
            return
        side = side.lower()
        if side.startswith("r"):
            ri = self._scaled_index(depth_i, config.SHAFT_DEPTH, len(self.right_down))
            self._main_pending[self.right_down[ri]] = color
        elif side.startswith("l"):
            li = self._scaled_index(depth_i, config.SHAFT_DEPTH, len(self.left_down))
            self._main_pending[self.left_down[li]] = color

    def set_shaft_sides(self, depth: int | float, right_color: Color, left_color: Color) -> None:
        self.set_shaft_side_depth("right", depth, right_color)
        self.set_shaft_side_depth("left", depth, left_color)

    def show(self) -> None:
        scale = self.output_scale
        for i, color in enumerate(self._main_pending):
            self.main[i] = scale_color(color, scale)
        for i, color in enumerate(self._top_pending):
            self.top[i] = scale_color(color, scale)
        self.main.show()
        self.top.show()

    @staticmethod
    def _scaled_index(depth: int, depth_count: int, physical_count: int) -> int:
        if physical_count <= 1:
            return 0
        if depth_count <= 1:
            return 0
        return max(0, min(physical_count - 1, round(depth * (physical_count - 1) / (depth_count - 1))))


def boot_animation(staff: StaffSurface, duration: float = 0.9) -> None:
    """Short, low-power boot indicator. Blocking is okay before runtime loop starts."""
    import time

    start = time.monotonic()
    while True:
        now = time.monotonic()
        t = (now - start) / duration
        if t >= 1.0:
            break
        staff.clear()
        depth = int(t * config.SHAFT_DEPTH)
        color = (20, 0, 0)
        staff.fill_top((10, 0, 0))
        for d in range(max(0, depth - 8), min(config.SHAFT_DEPTH, depth + 1)):
            staff.set_shaft_depth(d, color)
        for i in range(config.CONTROL_COUNT):
            if i / config.CONTROL_COUNT < t:
                staff.set_control(i, color)
        staff.set_output_scale(0.35)
        staff.show()
        time.sleep(1 / 60)
    staff.clear()
    staff.show()
PY

python - <<'PY'
from pathlib import Path
p = Path('animations/sparkle.py')
text = p.read_text()
text = text.replace('self.top = [BLACK for _ in range(config.TOP_COUNT)]', 'self.top = [BLACK for _ in range(config.TOP_COUNT)]')
# The TOP_COUNT constant is now the logical top count, so no further code changes
# are required beyond making sure no stale compiled files are used.
p.write_text(text)
PY

cat > tools/test_top_only.py <<'PY'
from __future__ import annotations

# Run with: sudo .venv/bin/python tools/test_top_only.py
import sys
from pathlib import Path
PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

import time
import config


def main():
    import board
    import neopixel

    pin = getattr(board, config.TOP_PIXEL_PIN)
    print(f"Testing TOP only on board.{config.TOP_PIXEL_PIN} with {config.TOP_COUNT} logical LEDs")
    print("The two physical 7-LED top strands should mirror each logical LED.")
    print("Example: logical top LED 3 should light LED 3 on both left and right strands.")
    print("Reminder: board.D12 = GPIO12 = physical pin 32. board.D18 = GPIO18 = physical pin 12.")

    pixels = neopixel.NeoPixel(
        pin,
        config.TOP_COUNT,
        brightness=0.25,
        auto_write=False,
        pixel_order=neopixel.RGB,
    )
    try:
        pixels.fill((0, 0, 0)); pixels.show(); time.sleep(0.25)
        for color_name, color in [("red", (80, 0, 0)), ("green", (0, 80, 0)), ("blue", (0, 0, 80)), ("white", (40, 40, 40))]:
            print(f"Both top strands should be {color_name}")
            pixels.fill(color); pixels.show(); time.sleep(0.8)

        print("Shared triangle side: first 2 mirrored LEDs")
        pixels.fill((0, 0, 0))
        for i in range(min(config.TOP_TRIANGLE_SHARED_COUNT, config.TOP_COUNT)):
            pixels[i] = (80, 80, 0)
        pixels.show(); time.sleep(1.2)

        print("Branch sides: remaining 5 mirrored LEDs")
        pixels.fill((0, 0, 0))
        for i in range(config.TOP_TRIANGLE_SHARED_COUNT, config.TOP_COUNT):
            pixels[i] = (0, 80, 80)
        pixels.show(); time.sleep(1.2)

        print("Mirrored logical chase: each step should appear on both strands")
        for _ in range(4):
            for i in range(config.TOP_COUNT):
                pixels.fill((0, 0, 0))
                pixels[i] = (80, 80, 80)
                pixels.show()
                time.sleep(0.12)
    finally:
        pixels.fill((0, 0, 0)); pixels.show()


if __name__ == "__main__":
    main()
PY

cat > main.py <<'PY'
from __future__ import annotations

import signal
import time
from pathlib import Path

import config
from animations import build_animations
from core.context import FrameContext
from core.debug import DebugDashboard, RuntimeLog, menu_value_text
from core.presets import PresetStore
from core.timing import FPSCounter
from hardware.audio import AudioProcessor
from hardware.beat import BeatTracker
from hardware.buttons import ButtonScanner
from hardware.imu import IMUReader
from hardware.leds import StaffSurface, boot_animation
from ui.menu import UIState
from ui.pages import build_pages


running = True

# New physical UI convention:
# - In settings: TL/TR change page; BL/BR change current setting value.
# - In run mode: TL/TR cycle saved presets; BL/BR are animation hotkeys.
PAGE_PREV = -1
PAGE_NEXT = 1
VALUE_DOWN = -1
VALUE_UP = 1
ANIM_PREV = -1
ANIM_NEXT = 1
PRESET_PREV = -1
PRESET_NEXT = 1


def handle_signal(signum, frame):
    global running
    running = False


def resolve_path(relative: str) -> Path:
    return Path(__file__).resolve().parent / relative


def main() -> int:
    global running
    signal.signal(signal.SIGINT, handle_signal)
    signal.signal(signal.SIGTERM, handle_signal)

    log = RuntimeLog()
    dashboard = DebugDashboard()
    log.add("LED staff runtime starting")

    staff = StaffSurface.create()
    staff.clear()
    staff.show()
    boot_animation(staff)

    buttons = ButtonScanner()
    imu = IMUReader(logger=log.add)
    audio = AudioProcessor(logger=log.add)
    beat = BeatTracker()
    audio.start()

    animations = build_animations()
    pages = build_pages()
    presets = PresetStore.load(resolve_path(config.PRESET_PATH), animation_count=len(animations))

    active_settings = presets.get(presets.last_active_slot)
    active_settings.clamp(animation_count=len(animations))
    pending_settings = active_settings.copy()
    ui = UIState(preset_slot=presets.last_active_slot)

    log.add(f"Loaded preset slot {presets.last_active_slot + 1}")
    log.add(f"Top geometry: {config.TOP_COUNT} logical mirrored LEDs; first {config.TOP_TRIANGLE_SHARED_COUNT} shared, remaining {config.TOP_TRIANGLE_BRANCH_COUNT} branch")

    fps = FPSCounter(config.FPS_LOG_INTERVAL)
    frame = 0
    last = time.monotonic()

    try:
        while running:
            frame_start = time.monotonic()
            dt = max(0.0001, min(0.1, frame_start - last))
            last = frame_start

            button_events = buttons.update(frame_start)

            imu_state = imu.update()
            audio_state = audio.snapshot(gain=active_settings.gain)
            beat_state = beat.update(frame_start, audio_state)

            if not ui.in_settings:
                if button_events["BC"].tap:
                    pending_settings = ui.enter_settings(frame_start, active_settings)
                    page = pages[ui.page_index]
                    log.add(f"Entered settings: {page.name} = {menu_value_text(page.name, pending_settings, ui, animations, pages, presets)}")

                # Run-mode preset cycling: TL previous preset, TR next preset.
                if button_events["TL"].tap or button_events["TR"].tap:
                    direction = PRESET_NEXT if button_events["TR"].tap else PRESET_PREV
                    ui.preset_slot = (ui.preset_slot + direction) % config.PRESET_SLOTS
                    presets.last_active_slot = ui.preset_slot
                    active_settings = presets.get(ui.preset_slot)
                    active_settings.clamp(animation_count=len(animations))
                    pending_settings = active_settings.copy()
                    try:
                        presets.save_file()
                    except Exception as exc:
                        log.add(f"Preset slot update failed to save: {exc}")
                    log.add(f"Loaded preset slot {ui.preset_slot + 1}: anim={animations[active_settings.animation_index % len(animations)].name} palette={active_settings.palette.name}")

                # Run-mode animation hotkeys: BL previous animation, BR next animation.
                if button_events["BL"].tap or button_events["BR"].tap:
                    direction = ANIM_NEXT if button_events["BR"].tap else ANIM_PREV
                    active_settings.animation_index = (active_settings.animation_index + direction) % max(1, len(animations))
                    pending_settings = active_settings.copy()
                    log.add(f"Animation hotkey: {animations[active_settings.animation_index % len(animations)].name}")
            else:
                if button_events["BC"].hold:
                    pending_settings = active_settings.copy()
                    log.add("Canceled settings with BC hold")
                    ui.exit_settings()
                elif button_events["BC"].tap:
                    page = pages[ui.page_index]
                    value_before_apply = menu_value_text(page.name, pending_settings, ui, animations, pages, presets)
                    replacement = page.on_apply(pending_settings, ui, presets, frame_start)
                    if replacement is not None:
                        pending_settings = replacement
                        pending_settings.clamp(animation_count=len(animations))
                    active_settings = pending_settings.copy()
                    active_settings.clamp(animation_count=len(animations))
                    log.add(f"Applied settings from {page.name}: {value_before_apply}")
                    ui.exit_settings()
                else:
                    # Settings page navigation: TL previous page, TR next page.
                    if button_events["TL"].tap:
                        ui.set_page(ui.page_index + PAGE_PREV, len(pages), frame_start)
                        page = pages[ui.page_index]
                        log.add(f"Menu page previous: {page.name} = {menu_value_text(page.name, pending_settings, ui, animations, pages, presets)}")
                    if button_events["TR"].tap:
                        ui.set_page(ui.page_index + PAGE_NEXT, len(pages), frame_start)
                        page = pages[ui.page_index]
                        log.add(f"Menu page next: {page.name} = {menu_value_text(page.name, pending_settings, ui, animations, pages, presets)}")

                    # Settings value changes: BL down/counter-clockwise, BR up/clockwise.
                    if button_events["BL"].tap:
                        page = pages[ui.page_index]
                        page.adjust(pending_settings, VALUE_DOWN, ui, len(animations), presets)
                        pending_settings.clamp(animation_count=len(animations))
                        ui.touch(frame_start)
                        log.add(f"{page.name} value down: {menu_value_text(page.name, pending_settings, ui, animations, pages, presets)}")
                    if button_events["BR"].tap:
                        page = pages[ui.page_index]
                        page.adjust(pending_settings, VALUE_UP, ui, len(animations), presets)
                        pending_settings.clamp(animation_count=len(animations))
                        ui.touch(frame_start)
                        log.add(f"{page.name} value up: {menu_value_text(page.name, pending_settings, ui, animations, pages, presets)}")

                    if ui.timed_out(frame_start):
                        pending_settings = active_settings.copy()
                        log.add("Settings timed out; pending changes canceled")
                        ui.exit_settings()

            staff.clear()
            staff.set_output_scale(active_settings.brightness)
            ctx = FrameContext(
                now=frame_start,
                dt=dt,
                frame=frame,
                settings=active_settings,
                beat=beat_state,
                imu=imu_state,
                audio=audio_state,
            )
            animation = animations[active_settings.animation_index % len(animations)]
            if beat_state.just_beat:
                animation.on_beat(ctx)
            animation.render_staff(staff, ctx)

            if ui.in_settings:
                pending_audio = audio.snapshot(gain=pending_settings.gain)
                circle_ctx = FrameContext(
                    now=frame_start,
                    dt=dt,
                    frame=frame,
                    settings=pending_settings,
                    beat=beat_state,
                    imu=imu_state,
                    audio=pending_audio,
                )
                pages[ui.page_index].render_circle(staff, circle_ctx, ui, animations)

            staff.show()

            report = fps.tick(frame_start)
            if report is not None and not dashboard.enabled:
                log.add(
                    f"fps={report:.1f} mode={'settings' if ui.in_settings else 'run'} "
                    f"preset={ui.preset_slot + 1} anim={animation.name} palette={active_settings.palette.name} "
                    f"speed={active_settings.speed.name} bpm={beat_state.bpm_smooth:.1f}"
                )

            dashboard.render(
                now=frame_start,
                frame=frame,
                fps_report=report,
                ui=ui,
                pages=pages,
                animations=animations,
                active_settings=active_settings,
                pending_settings=pending_settings,
                imu_state=imu_state,
                audio_state=audio_state,
                beat_state=beat_state,
                log=log,
                presets=presets,
            )

            frame += 1
            elapsed = time.monotonic() - frame_start
            sleep_time = config.FRAME_TIME - elapsed
            if sleep_time > 0:
                time.sleep(sleep_time)
    finally:
        log.add("LED staff runtime stopping")
        audio.stop()
        staff.clear()
        staff.show()
        try:
            buttons.cleanup()
        except Exception:
            pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PY

# Force Python to ignore stale .pyc files after the geometry/control changes.
find . -type d -name __pycache__ -prune -exec rm -rf {} +

python -m compileall -q config.py main.py core hardware animations ui tools

echo "Top geometry + UI controls patch applied."
echo "Next: sudo LED_STAFF_AUDIO=1 .venv/bin/python tools/test_top_only.py"
echo "Then: sudo LED_STAFF_AUDIO=1 .venv/bin/python main.py"
