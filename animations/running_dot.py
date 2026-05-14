from __future__ import annotations

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
