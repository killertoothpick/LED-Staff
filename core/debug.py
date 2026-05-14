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
    return ""
