#!/usr/bin/env bash
set -euo pipefail

cd "${1:-$(pwd)}"

if [[ ! -f main.py || ! -f config.py ]]; then
  echo "Run this from the led_staff_v1 project root, or pass the project path as the first argument." >&2
  exit 1
fi

backup_dir="backups/debug_menu_patch_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$backup_dir"
cp -a main.py config.py hardware/leds.py hardware/audio.py hardware/imu.py ui/pages.py "$backup_dir"/
mkdir -p core
[[ -f core/debug.py ]] && cp -a core/debug.py "$backup_dir/debug.py" || true

echo "Backed up files to $backup_dir"

python - <<'PY'
from pathlib import Path
import re

# ---------------------------------------------------------------------------
# config.py: add debug console and dial-direction constants without touching
# the confirmed hardware/button mapping.
# ---------------------------------------------------------------------------
p = Path('config.py')
text = p.read_text()

if 'CONTROL_DIAL_ZERO' not in text:
    marker = 'CONTROL_COUNT = CONTROL_END - CONTROL_START + 1\n'
    insert = '''\n# Logical direction for the 16-LED control circle while using it as a dial.\n# Increase moves clockwise; decrease moves counter-clockwise. If the physical\n# ring ever appears reversed, flip CONTROL_DIAL_CLOCKWISE between 1 and -1.\nCONTROL_DIAL_ZERO = 0\nCONTROL_DIAL_CLOCKWISE = -1\n'''
    if marker not in text:
        raise SystemExit('Could not find CONTROL_COUNT line in config.py')
    text = text.replace(marker, marker + insert)
else:
    text = re.sub(r'^CONTROL_DIAL_ZERO\s*=.*$', 'CONTROL_DIAL_ZERO = 0', text, flags=re.M)
    text = re.sub(r'^CONTROL_DIAL_CLOCKWISE\s*=.*$', 'CONTROL_DIAL_CLOCKWISE = -1', text, flags=re.M)

if 'DEBUG_CONSOLE' not in text:
    text += '''\n# Live terminal dashboard. Enabled by default when run manually in a terminal.\n# Use LED_STAFF_DEBUG=0 to go back to plain logs.\nDEBUG_CONSOLE = os.environ.get("LED_STAFF_DEBUG", "1") != "0"\nDEBUG_CONSOLE_HZ = float(os.environ.get("LED_STAFF_DEBUG_HZ", "4"))\nDEBUG_LOG_LINES = int(os.environ.get("LED_STAFF_DEBUG_LOG_LINES", "8"))\n'''
else:
    # Keep existing values if present, but make sure all three exist.
    if 'DEBUG_CONSOLE_HZ' not in text:
        text += '\nDEBUG_CONSOLE_HZ = float(os.environ.get("LED_STAFF_DEBUG_HZ", "4"))\n'
    if 'DEBUG_LOG_LINES' not in text:
        text += '\nDEBUG_LOG_LINES = int(os.environ.get("LED_STAFF_DEBUG_LOG_LINES", "8"))\n'

p.write_text(text)

# ---------------------------------------------------------------------------
# hardware/leds.py: add logical clockwise dial helpers for the control circle.
# ---------------------------------------------------------------------------
p = Path('hardware/leds.py')
text = p.read_text()
if 'def control_dial_index' not in text:
    old = '''    def set_control(self, index: int, color: Color) -> None:\n        if 0 <= index < config.CONTROL_COUNT:\n            self._main_pending[config.CONTROL_START + index] = color\n\n    def fill_control(self, color: Color) -> None:\n        for i in range(config.CONTROL_COUNT):\n            self.set_control(i, color)\n'''
    new = '''    def set_control(self, index: int, color: Color) -> None:\n        if 0 <= index < config.CONTROL_COUNT:\n            self._main_pending[config.CONTROL_START + index] = color\n\n    def control_dial_index(self, step: int | float) -> int:\n        """Map logical clockwise dial steps to the physical control-ring index."""\n        step_i = int(round(step))\n        return (config.CONTROL_DIAL_ZERO + config.CONTROL_DIAL_CLOCKWISE * step_i) % config.CONTROL_COUNT\n\n    def set_control_dial(self, step: int | float, color: Color) -> None:\n        self.set_control(self.control_dial_index(step), color)\n\n    def fill_control(self, color: Color) -> None:\n        for i in range(config.CONTROL_COUNT):\n            self.set_control(i, color)\n'''
    if old not in text:
        raise SystemExit('Could not patch hardware/leds.py automatically; set_control block differed from expected')
    text = text.replace(old, new)
p.write_text(text)

# ---------------------------------------------------------------------------
# ui/pages.py: use logical dial positions for menu/control-circle previews.
# ---------------------------------------------------------------------------
p = Path('ui/pages.py')
text = p.read_text()
if 'set_control_dial' not in text:
    text = text.replace('staff.set_control(i,', 'staff.set_control_dial(i,')
    text = text.replace('staff.set_control((pos - offset) % config.CONTROL_COUNT,', 'staff.set_control_dial((pos - offset) % config.CONTROL_COUNT,')
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
    ) -> None:
        if fps_report is not None:
            self._last_fps = fps_report
        if not self.enabled or now < self._next_render_at:
            return
        self._next_render_at = now + self.interval

        mode = "SETTINGS" if ui.in_settings else "RUN"
        active_animation = animations[active_settings.animation_index % len(animations)].name if animations else "none"
        pending_animation = animations[pending_settings.animation_index % len(animations)].name if animations else "none"

        lines: list[str] = []
        lines.append("LED STAFF DEBUG  |  Ctrl+C exits  |  LED_STAFF_DEBUG=0 disables this screen")
        lines.append("=" * 78)
        lines.append(f"Mode: {mode:<9} Frame: {frame:<8} FPS: {self._fmt(self._last_fps, 1):>6}")
        lines.append(f"Beat: bpm={beat_state.bpm_smooth:6.1f} raw={beat_state.bpm:6.1f} phase={beat_state.phase:4.2f} confidence={beat_state.confidence:4.2f} just_beat={beat_state.just_beat}")
        lines.append(f"Audio: vol={audio_state.volume:5.3f} smooth={audio_state.volume_smooth:5.3f} bass={audio_state.bass:5.3f} mids={audio_state.mids:5.3f} treble={audio_state.treble:5.3f} clipped={audio_state.clipped}")
        lines.append(f"IMU: available={imu_state.available} motion={imu_state.motion:5.2f} tilt_x={imu_state.tilt_x:6.2f} tilt_y={imu_state.tilt_y:6.2f} accel=({imu_state.ax:5.2f}, {imu_state.ay:5.2f}, {imu_state.az:5.2f})")
        lines.append("")
        lines.append("Active settings")
        lines.append(f"  Animation : {active_animation}")
        lines.append(f"  Palette   : {active_settings.palette.name}")
        lines.append(f"  Speed     : {active_settings.speed.name}")
        lines.append(f"  Brightness: {active_settings.brightness:.2f}  index {active_settings.brightness_index + 1}/{len(BRIGHTNESS_OPTIONS)}")
        lines.append(f"  Gain      : {active_settings.gain:.2f}  index {active_settings.gain_index + 1}/{len(GAIN_OPTIONS)}")

        if ui.in_settings:
            page = pages[ui.page_index]
            value = menu_value_text(page.name, pending_settings, ui, animations, pages, presets=None)
            lines.append("")
            lines.append("Current menu")
            lines.append(f"  Page      : {ui.page_index + 1}/{len(pages)}  {page.name}")
            lines.append(f"  Value     : {value}")
            lines.append(f"  Pending animation: {pending_animation}")
            lines.append("  Controls  : TL/left = counter-clockwise / down, TR/right = clockwise / up")
            lines.append("              BL = previous page, BR = next page, BC tap = apply, BC hold = cancel")
        else:
            lines.append("")
            lines.append("Controls")
            lines.append("  BC tap enters settings. In menus, right-side buttons move clockwise/up; left-side buttons move counter-clockwise/down.")

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
            loaded = f" anim={s.animation_index + 1} palette={s.palette.name} speed={s.speed.name}"
        return f"Preset slot {ui.preset_slot + 1}/{config.PRESET_SLOTS}{loaded}"
    return ""
PY

cat > hardware/imu.py <<'PY'
from __future__ import annotations

import math
import time
from collections.abc import Callable

import config
from core.context import IMUState


class IMUReader:
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
            self._logger("IMU initialized")
        except Exception as exc:
            self.sensor = None
            self.available = False
            self._logger(f"IMU unavailable, continuing without it: {exc}")

    def update(self) -> IMUState:
        if not self.available or self.sensor is None:
            self.last = IMUState(available=False)
            return self.last
        try:
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

# Menu/dial direction convention:
# right-side controls increase and rotate clockwise, left-side controls decrease
# and rotate counter-clockwise.
DIAL_COUNTER_CLOCKWISE = -1
DIAL_CLOCKWISE = 1


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
                    log.add(f"Entered settings: {pages[ui.page_index].name} = {menu_value_text(pages[ui.page_index].name, pending_settings, ui, animations, pages, presets)}")
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
                    if button_events["BL"].tap:
                        ui.set_page(ui.page_index + DIAL_COUNTER_CLOCKWISE, len(pages), frame_start)
                        log.add(f"Menu page counter-clockwise: {pages[ui.page_index].name} = {menu_value_text(pages[ui.page_index].name, pending_settings, ui, animations, pages, presets)}")
                    if button_events["BR"].tap:
                        ui.set_page(ui.page_index + DIAL_CLOCKWISE, len(pages), frame_start)
                        log.add(f"Menu page clockwise: {pages[ui.page_index].name} = {menu_value_text(pages[ui.page_index].name, pending_settings, ui, animations, pages, presets)}")
                    if button_events["TL"].tap:
                        page = pages[ui.page_index]
                        page.adjust(pending_settings, DIAL_COUNTER_CLOCKWISE, ui, len(animations), presets)
                        pending_settings.clamp(animation_count=len(animations))
                        ui.touch(frame_start)
                        log.add(f"{page.name} counter-clockwise: {menu_value_text(page.name, pending_settings, ui, animations, pages, presets)}")
                    if button_events["TR"].tap:
                        page = pages[ui.page_index]
                        page.adjust(pending_settings, DIAL_CLOCKWISE, ui, len(animations), presets)
                        pending_settings.clamp(animation_count=len(animations))
                        ui.touch(frame_start)
                        log.add(f"{page.name} clockwise: {menu_value_text(page.name, pending_settings, ui, animations, pages, presets)}")
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
                    f"anim={animation.name} palette={active_settings.palette.name} "
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

python -m compileall -q main.py core hardware ui animations

echo "Done. Test with: sudo LED_STAFF_AUDIO=1 .venv/bin/python main.py"
echo "Plain logs instead of live dashboard: sudo LED_STAFF_AUDIO=1 LED_STAFF_DEBUG=0 .venv/bin/python main.py"
