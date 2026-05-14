from __future__ import annotations

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
