#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f "config.py" || ! -f "main.py" ]]; then
  echo "Run this from the led_staff_v1 project root." >&2
  exit 1
fi

STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="backups/preset_direction_patch_${STAMP}"
mkdir -p "$BACKUP_DIR"
for f in config.py main.py core/presets.py core/debug.py ui/pages.py hardware/leds.py animations/charge.py animations/running_dot.py tools/test_top_only.py; do
  [[ -f "$f" ]] && cp "$f" "$BACKUP_DIR/$(basename "$f")"
done

python - <<'PY'
from pathlib import Path
import re

# ---------- config.py ----------
p = Path('config.py')
text = p.read_text()
text = re.sub(r'^PRESET_SLOTS\s*=\s*\d+', 'PRESET_SLOTS = 9', text, flags=re.M)
if 'RANDOM_VISUAL_PRESET_COUNT' not in text:
    text = re.sub(
        r'(PRESET_SLOTS\s*=\s*9\s*)',
        r'\1\n# The last N preset slots keep saved mechanism settings, but get a fresh\n# random visual pairing (animation + palette) at each boot.\nRANDOM_VISUAL_PRESET_COUNT = 5\n',
        text,
        count=1,
    )
# Ensure button timing constants exist, because older patches may not have added them.
insert_after = None
m = re.search(r'BUTTON_PINS\s*=\s*\{.*?\}\s*', text, flags=re.S)
if m:
    insert_after = m.end()
for name, value in [('BUTTON_DEBOUNCE_SEC', '0.030'), ('BUTTON_HOLD_SEC', '1.0'), ('SETTINGS_TIMEOUT_SEC', '15.0')]:
    if not re.search(rf'^{name}\s*=', text, flags=re.M):
        if insert_after is None:
            text += f'\n{name} = {value}\n'
        else:
            text = text[:insert_after] + f'\n{name} = {value}\n' + text[insert_after:]
            insert_after += len(f'\n{name} = {value}\n')
p.write_text(text)

# ---------- core/presets.py ----------
Path('core/presets.py').write_text(r'''from __future__ import annotations

import json
import os
import random
from dataclasses import dataclass
from pathlib import Path

import config
from core.palettes import PALETTES
from core.settings import Settings


@dataclass
class PresetStore:
    path: Path
    presets: list[Settings]
    last_active_slot: int = 0

    @classmethod
    def load(cls, path: str | Path, animation_count: int | None = None) -> "PresetStore":
        path = Path(path)
        presets = [Settings() for _ in range(config.PRESET_SLOTS)]
        last_active_slot = 0
        try:
            if path.exists():
                data = json.loads(path.read_text())
                last_active_slot = int(data.get("last_active_slot", 0)) % config.PRESET_SLOTS
                loaded = data.get("presets", [])
                for i, item in enumerate(loaded[:config.PRESET_SLOTS]):
                    settings_data = item.get("settings", item) if isinstance(item, dict) else {}
                    presets[i] = Settings.from_json(settings_data)
                    presets[i].clamp(animation_count)
        except Exception as exc:
            print(f"Preset load failed, using defaults: {exc}")

        store = cls(path=path, presets=presets, last_active_slot=last_active_slot)
        store.randomize_boot_visual_slots(animation_count)
        return store

    def randomize_boot_visual_slots(self, animation_count: int | None) -> None:
        """Give the last preset slots fresh visuals at boot.

        Only animation_index and palette_index are randomized. Mechanism settings
        such as speed, brightness, and gain stay exactly as saved in the file.
        The randomization is intentionally not written immediately; it is the
        starting visual for this boot. It will be saved only if the user changes
        away from that slot or otherwise persists the current slot.
        """
        count = max(0, int(getattr(config, "RANDOM_VISUAL_PRESET_COUNT", 0)))
        if count <= 0:
            return
        start = max(0, config.PRESET_SLOTS - count)
        safe_animation_count = max(1, int(animation_count or 1))
        for slot in range(start, config.PRESET_SLOTS):
            preset = self.presets[slot]
            preset.animation_index = random.randrange(safe_animation_count)
            preset.palette_index = random.randrange(len(PALETTES))
            preset.clamp(animation_count)

    def save_file(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        data = {
            "version": 2,
            "last_active_slot": self.last_active_slot % config.PRESET_SLOTS,
            "random_visual_preset_count": getattr(config, "RANDOM_VISUAL_PRESET_COUNT", 0),
            "presets": [
                {"name": f"Preset {i + 1}", "settings": preset.to_json()}
                for i, preset in enumerate(self.presets[:config.PRESET_SLOTS])
            ],
        }
        tmp = self.path.with_suffix(self.path.suffix + ".tmp")
        tmp.write_text(json.dumps(data, indent=2))
        os.replace(tmp, self.path)

    def get(self, slot: int) -> Settings:
        return self.presets[slot % config.PRESET_SLOTS].copy()

    def save_current(self, slot: int, settings: Settings, *, remember: bool = True) -> None:
        """Save the current runtime settings into a slot and write presets.json."""
        slot %= config.PRESET_SLOTS
        self.presets[slot] = settings.copy()
        if remember:
            self.last_active_slot = slot
        self.save_file()

    def remember_active_slot(self, slot: int) -> None:
        slot %= config.PRESET_SLOTS
        self.last_active_slot = slot
        self.save_file()

    def set(self, slot: int, settings: Settings) -> None:
        self.save_current(slot, settings, remember=True)
''')

# ---------- ui/pages.py ----------
# Remove Save/Load from active menus. The classes are not needed anymore, so keep the file smaller.
Path('ui/pages.py').write_text(r'''from __future__ import annotations

import math

import config
from animations.base import Animation
from core.colors import WHITE, scale_color, wheel
from core.context import FrameContext
from core.palettes import PALETTES
from core.presets import PresetStore
from core.settings import BRIGHTNESS_OPTIONS, GAIN_OPTIONS, SPEED_OPTIONS, Settings
from hardware.leds import StaffSurface
from ui.menu import UIState


class SettingsPage:
    name = "Page"

    def adjust(self, settings: Settings, direction: int, ui: UIState, animation_count: int, presets: PresetStore | None = None) -> None:
        pass

    def on_apply(self, settings: Settings, ui: UIState, presets: PresetStore | None, now: float) -> Settings | None:
        return None

    def render_circle(self, staff: StaffSurface, ctx: FrameContext, ui: UIState, animations: list[Animation]) -> None:
        self._render_intro_or_preview(staff, ctx, ui)

    def _intro_t(self, ctx: FrameContext, ui: UIState, duration: float = 0.75) -> float:
        return max(0.0, min(1.0, (ctx.now - ui.entered_page_at) / duration))

    def _render_intro_or_preview(self, staff: StaffSurface, ctx: FrameContext, ui: UIState) -> None:
        for i in range(config.CONTROL_COUNT):
            staff.set_control_dial(i, ctx.settings.palette.sample(i / config.CONTROL_COUNT, ctx.now * 0.05))


class AnimationPage(SettingsPage):
    name = "Animation"

    def adjust(self, settings: Settings, direction: int, ui: UIState, animation_count: int, presets: PresetStore | None = None) -> None:
        settings.animation_index = (settings.animation_index + direction) % max(1, animation_count)

    def render_circle(self, staff: StaffSurface, ctx: FrameContext, ui: UIState, animations: list[Animation]) -> None:
        if animations:
            animations[ctx.settings.animation_index % len(animations)].render_preview(staff, ctx)


class PalettePage(SettingsPage):
    name = "Palette"

    def adjust(self, settings: Settings, direction: int, ui: UIState, animation_count: int, presets: PresetStore | None = None) -> None:
        settings.palette_index = (settings.palette_index + direction) % len(PALETTES)

    def render_circle(self, staff: StaffSurface, ctx: FrameContext, ui: UIState, animations: list[Animation]) -> None:
        t = self._intro_t(ctx, ui)
        phase = ctx.now * 0.15
        if t < 1.0:
            # Page identity: rainbow spin. Right/value-up rotates clockwise.
            for i in range(config.CONTROL_COUNT):
                staff.set_control_dial(i, wheel((i / config.CONTROL_COUNT + ctx.now * 0.8) * 255))
        else:
            for i in range(config.CONTROL_COUNT):
                staff.set_control_dial(i, ctx.settings.palette.sample(i / config.CONTROL_COUNT, phase))


class SpeedPage(SettingsPage):
    name = "Speed"

    def adjust(self, settings: Settings, direction: int, ui: UIState, animation_count: int, presets: PresetStore | None = None) -> None:
        settings.speed_index = (settings.speed_index + direction) % len(SPEED_OPTIONS)

    def render_circle(self, staff: StaffSurface, ctx: FrameContext, ui: UIState, animations: list[Animation]) -> None:
        option = ctx.settings.speed
        for i in range(config.CONTROL_COUNT):
            staff.set_control_dial(i, scale_color(ctx.settings.palette.sample(i / config.CONTROL_COUNT, 0), 0.04))
        if option.mode == "beat":
            base = 0.2 + (0.8 if ctx.beat.just_beat else 0.0)
            for i in range(config.CONTROL_COUNT):
                staff.set_control_dial(i, scale_color(ctx.settings.palette.sample(i / config.CONTROL_COUNT, ctx.now * 0.04), base))
            pos = int(ctx.beat.phase * config.CONTROL_COUNT) % config.CONTROL_COUNT
        else:
            speed = float(option.multiplier or 1.0)
            pos = int(ctx.now * (2 + speed * 5)) % config.CONTROL_COUNT
        for offset in range(3):
            staff.set_control_dial((pos - offset) % config.CONTROL_COUNT, scale_color(WHITE, 1.0 - offset * 0.25))


class BrightnessPage(SettingsPage):
    name = "Brightness"

    def adjust(self, settings: Settings, direction: int, ui: UIState, animation_count: int, presets: PresetStore | None = None) -> None:
        settings.brightness_index = (settings.brightness_index + direction) % len(BRIGHTNESS_OPTIONS)

    def render_circle(self, staff: StaffSurface, ctx: FrameContext, ui: UIState, animations: list[Animation]) -> None:
        t = self._intro_t(ctx, ui)
        level = math.sin(t * math.pi) if t < 1.0 else ctx.settings.brightness
        for i in range(config.CONTROL_COUNT):
            staff.set_control_dial(i, scale_color(WHITE, level))


class GainPage(SettingsPage):
    name = "Gain"

    def adjust(self, settings: Settings, direction: int, ui: UIState, animation_count: int, presets: PresetStore | None = None) -> None:
        settings.gain_index = (settings.gain_index + direction) % len(GAIN_OPTIONS)

    def render_circle(self, staff: StaffSurface, ctx: FrameContext, ui: UIState, animations: list[Animation]) -> None:
        meter = max(ctx.audio.volume_smooth, (ctx.settings.gain_index + 1) / len(GAIN_OPTIONS) * 0.25)
        lit = int(round(meter * config.CONTROL_COUNT))
        for i in range(config.CONTROL_COUNT):
            intensity = 1.0 if i < lit else 0.08
            staff.set_control_dial(i, scale_color(ctx.settings.palette.sample(i / config.CONTROL_COUNT, 0), intensity))


def build_pages() -> list[SettingsPage]:
    # Save/Load pages are intentionally removed. Presets are now managed from
    # run mode: TL/TR auto-save the current slot and load the neighboring slot.
    return [
        AnimationPage(),
        PalettePage(),
        SpeedPage(),
        BrightnessPage(),
        GainPage(),
    ]
''')

# ---------- hardware/leds.py: base-to-top boot sweep + keep top chase visible ----------
p = Path('hardware/leds.py')
text = p.read_text()
old = r'''def boot_animation(staff: StaffSurface, duration: float = 0.9) -> None:
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
'''
new = r'''def boot_animation(staff: StaffSurface, duration: float = 1.15) -> None:
    """Short, low-power boot indicator.

    The shaft sweep now travels from the base toward the top. The top keeps the
    mirrored 7-LED chase from hardware testing because it looked good and proves
    the top geometry at every boot.
    """
    import time

    start = time.monotonic()
    while True:
        now = time.monotonic()
        t = (now - start) / duration
        if t >= 1.0:
            break
        staff.clear()
        depth_from_base = int(t * config.SHAFT_DEPTH)
        color = (20, 0, 0)

        # Base-to-top sweep: logical shaft depth 0 is the physical top, so invert.
        for d in range(max(0, depth_from_base - 8), min(config.SHAFT_DEPTH, depth_from_base + 1)):
            staff.set_shaft_depth(config.SHAFT_DEPTH - 1 - d, color)

        # Keep the fantastic mirrored top chase around.
        chase = int(now * 12) % max(1, config.TOP_COUNT)
        for i in range(config.TOP_COUNT):
            distance = min((i - chase) % config.TOP_COUNT, (chase - i) % config.TOP_COUNT)
            intensity = max(0.0, 1.0 - distance / 3.0)
            staff.set_top_pixel(i, scale_color((40, 20, 0), intensity))

        for i in range(config.CONTROL_COUNT):
            if i / config.CONTROL_COUNT < t:
                staff.set_control_dial(i, color)
        staff.set_output_scale(0.35)
        staff.show()
        time.sleep(1 / 60)
    staff.clear()
    staff.show()
'''
if old in text:
    text = text.replace(old, new)
else:
    # Fall back: replace from def boot_animation to EOF.
    text = re.sub(r'def boot_animation\(staff: StaffSurface, duration: float = .*?\n\Z', new, text, flags=re.S)
p.write_text(text)

# ---------- animations/charge.py: base-to-top travel ----------
Path('animations/charge.py').write_text(r'''from __future__ import annotations

import config
from animations.base import Animation
from core.colors import scale_color
from core.context import FrameContext
from hardware.leds import StaffSurface


class Charge(Animation):
    name = "Charge"

    def __init__(self) -> None:
        self.phase = 0.0
        self.beat_flash = 0.0

    def on_beat(self, ctx: FrameContext) -> None:
        self.beat_flash = 1.0

    def render_staff(self, staff: StaffSurface, ctx: FrameContext) -> None:
        step = self._step(ctx)
        self.phase = (self.phase + step * 32.0) % 75.0
        self.beat_flash = max(0.0, self.beat_flash - ctx.dt * 5.0)

        palette = ctx.settings.palette
        base_phase = ctx.now * 0.03
        audio_boost = ctx.audio.bass * 0.8 + self.beat_flash * 0.5
        motion_boost = min(0.5, max(0.0, (ctx.imu.motion - 9.8) / 20.0)) if ctx.imu.available else 0.0

        # The charge wave now travels from the base of the staff toward the top.
        # animation_depth 0 = base, animation_depth SHAFT_DEPTH-1 = top.
        for animation_depth in range(config.SHAFT_DEPTH):
            k = animation_depth - self.phase
            l = 74 - (k % 75)
            intensity = 1.0 / l if l else 1.0
            intensity = min(1.0, intensity * 8.0 + audio_boost + motion_boost)
            color = scale_color(palette.sample(animation_depth / config.SHAFT_DEPTH, base_phase), intensity)
            staff.set_shaft_depth(config.SHAFT_DEPTH - 1 - animation_depth, color)

        # Top glows as the wave approaches/reaches the top, plus beat/audio punch.
        distance_to_top = abs((config.SHAFT_DEPTH - 1) - (self.phase % config.SHAFT_DEPTH))
        arrival = max(0.0, 1.0 - distance_to_top / 18.0)
        top_intensity = min(1.0, 0.10 + audio_boost + self.beat_flash * 0.6 + arrival * 0.7)
        staff.fill_top(scale_color(palette.sample(1.0, base_phase), top_intensity))

    def render_preview(self, staff: StaffSurface, ctx: FrameContext) -> None:
        palette = ctx.settings.palette
        phase = int(ctx.now * 20) % config.CONTROL_COUNT
        for i in range(config.CONTROL_COUNT):
            # Preview also reads as base-to-top / clockwise progress.
            dist = (phase - i) % config.CONTROL_COUNT
            intensity = max(0.0, 1.0 - dist / 8.0)
            staff.set_control_dial(i, scale_color(palette.sample(i / config.CONTROL_COUNT, ctx.now * 0.05), intensity))

    def _step(self, ctx: FrameContext) -> float:
        speed = ctx.settings.speed
        if speed.mode == "beat":
            return 1.0 if ctx.beat.just_beat else ctx.dt * (ctx.beat.bpm_smooth / 60.0) * 0.15
        return ctx.dt * float(speed.multiplier or 1.0)
''')

# ---------- animations/running_dot.py: default base-to-top, tilt can still reverse ----------
Path('animations/running_dot.py').write_text(r'''from __future__ import annotations

import config
from animations.base import Animation
from core.colors import scale_color
from core.context import FrameContext
from hardware.leds import StaffSurface


class RunningDot(Animation):
    name = "Running Dot"

    def __init__(self) -> None:
        self.pos = 0.0  # animation space: 0=base, SHAFT_DEPTH-1=top

    def on_beat(self, ctx: FrameContext) -> None:
        if ctx.settings.speed.mode == "beat":
            self.pos += 6.0

    def render_staff(self, staff: StaffSurface, ctx: FrameContext) -> None:
        speed = ctx.settings.speed
        if speed.mode == "fixed":
            # Default movement is base -> top. Strong downward tilt reverses it.
            tilt = 0.0
            if ctx.imu.available:
                # Axis convention confirmed: Y is up.
                tilt = max(-1.0, min(1.0, ctx.imu.ay / 9.80665))
            direction = -1.0 if tilt < -0.35 else 1.0
            self.pos += direction * ctx.dt * 35.0 * float(speed.multiplier or 1.0)
        else:
            self.pos += ctx.dt * max(1.0, ctx.beat.bpm_smooth / 60.0) * 2.0

        palette = ctx.settings.palette
        pos = self.pos % config.SHAFT_DEPTH
        tail = 5 + int(ctx.audio.volume_smooth * 12)
        for animation_depth in range(config.SHAFT_DEPTH):
            dist = min((animation_depth - pos) % config.SHAFT_DEPTH, (pos - animation_depth) % config.SHAFT_DEPTH)
            intensity = max(0.0, 1.0 - dist / max(1, tail))
            color = scale_color(palette.sample(animation_depth / config.SHAFT_DEPTH, ctx.now * 0.05), intensity)
            staff.set_shaft_depth(config.SHAFT_DEPTH - 1 - animation_depth, color)

        top_proximity = max(0.0, 1.0 - abs((config.SHAFT_DEPTH - 1) - pos) / 18.0)
        top_color = palette.sample(1.0, ctx.now * 0.05)
        staff.fill_top(scale_color(top_color, 0.15 + ctx.audio.volume_smooth * 0.5 + top_proximity * 0.65))

    def render_preview(self, staff: StaffSurface, ctx: FrameContext) -> None:
        palette = ctx.settings.palette
        pos = int(ctx.now * 8) % config.CONTROL_COUNT
        for i in range(config.CONTROL_COUNT):
            dist = min((i - pos) % config.CONTROL_COUNT, (pos - i) % config.CONTROL_COUNT)
            staff.set_control_dial(i, scale_color(palette.sample(i / config.CONTROL_COUNT, 0), max(0.0, 1.0 - dist / 4)))
''')

# ---------- core/debug.py: updated preset/menu messaging ----------
p = Path('core/debug.py')
text = p.read_text()
text = text.replace('  TL/TR cycle saved presets\n  BL/BR animation hotkeys: previous/next animation', '  TL/TR auto-save current slot, then load previous/next preset\n  BL/BR animation hotkeys: previous/next animation and save current slot')
text = text.replace('  Logical top LEDs: {config.TOP_COUNT}; two physical 7-LED strands mirror each logical index', '  Logical top LEDs: {config.TOP_COUNT}; two physical 7-LED strands mirror each logical index')
# Remove Save/Load menu value branches if present; harmless but stale.
text = re.sub(r'\n    if name == "save":\n        return f"Preset slot \{ui\.preset_slot \+ 1\}/\{config\.PRESET_SLOTS\}"\n    if name == "load":\n        loaded = ""\n        if presets is not None:\n            s = presets\.get\(ui\.preset_slot\)\n            loaded_anim = animations\[s\.animation_index % len\(animations\)\]\.name if animations else str\(s\.animation_index \+ 1\)\n            loaded = f" anim=\{loaded_anim\} palette=\{s\.palette\.name\} speed=\{s\.speed\.name\}"\n        return f"Preset slot \{ui\.preset_slot \+ 1\}/\{config\.PRESET_SLOTS\}\{loaded\}"', '', text)
p.write_text(text)

# ---------- main.py: preset cycling auto-save/load; settings/hotkeys persist ----------
Path('main.py').write_text(r'''from __future__ import annotations

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

# Physical UI convention:
# - In settings: TL/TR change page; BL/BR change current setting value.
# - In run mode: TL/TR save current preset and load previous/next preset.
# - In run mode: BL/BR are animation hotkeys and save the current preset.
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


def animation_name(animations, settings) -> str:
    if not animations:
        return "none"
    return animations[settings.animation_index % len(animations)].name


def save_slot(log: RuntimeLog, presets: PresetStore, slot: int, settings, *, reason: str) -> None:
    try:
        presets.save_current(slot, settings, remember=True)
        log.add(f"Saved preset slot {slot + 1}: {reason}")
    except Exception as exc:
        log.add(f"Preset save failed for slot {slot + 1}: {exc}")


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
    log.add(f"Preset model: {config.PRESET_SLOTS} slots; last {getattr(config, 'RANDOM_VISUAL_PRESET_COUNT', 0)} start with random visuals at boot")
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

                # Run-mode preset cycling: save the slot we are leaving, then load the neighboring slot.
                if button_events["TL"].tap or button_events["TR"].tap:
                    old_slot = ui.preset_slot % config.PRESET_SLOTS
                    direction = PRESET_NEXT if button_events["TR"].tap else PRESET_PREV
                    save_slot(log, presets, old_slot, active_settings, reason="leaving slot")

                    ui.preset_slot = (old_slot + direction) % config.PRESET_SLOTS
                    presets.last_active_slot = ui.preset_slot
                    active_settings = presets.get(ui.preset_slot)
                    active_settings.clamp(animation_count=len(animations))
                    pending_settings = active_settings.copy()
                    try:
                        presets.remember_active_slot(ui.preset_slot)
                    except Exception as exc:
                        log.add(f"Preset active-slot save failed: {exc}")
                    log.add(f"Loaded preset slot {ui.preset_slot + 1}: anim={animation_name(animations, active_settings)} palette={active_settings.palette.name} speed={active_settings.speed.name} brightness={active_settings.brightness:.2f} gain={active_settings.gain:.2f}")

                # Run-mode animation hotkeys: BL previous animation, BR next animation; persist current slot.
                if button_events["BL"].tap or button_events["BR"].tap:
                    direction = ANIM_NEXT if button_events["BR"].tap else ANIM_PREV
                    active_settings.animation_index = (active_settings.animation_index + direction) % max(1, len(animations))
                    pending_settings = active_settings.copy()
                    save_slot(log, presets, ui.preset_slot, active_settings, reason="animation hotkey")
                    log.add(f"Animation hotkey: {animation_name(animations, active_settings)}")
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
                    save_slot(log, presets, ui.preset_slot, active_settings, reason=f"applied {page.name}")
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
''')

# ---------- tools/test_top_only.py: explicitly keep chase test around ----------
p = Path('tools/test_top_only.py')
text = p.read_text()
text = text.replace('print("Mirrored logical chase: each step should appear on both strands")', 'print("Mirrored logical chase kept intentionally: each step should appear on both strands")')
p.write_text(text)
PY

python -m compileall -q config.py main.py core hardware ui animations tools

echo "Applied preset/direction patch. Backups are in $BACKUP_DIR"
echo "Key changes: 9 preset slots, no Save/Load pages, preset cycling auto-saves current slot then loads next, last 5 slots get random animation+palette on boot, non-motion animations move base-to-top."
