from __future__ import annotations

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
