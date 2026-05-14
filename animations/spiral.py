from __future__ import annotations

import math

import config
from animations.base import Animation
from core.colors import wheel, scale_color
from core.context import FrameContext
from hardware.leds import StaffSurface


class TiltSpiral(Animation):
    name = "Tilt Spiral"

    def __init__(self) -> None:
        self.count = 0.0
        self.pace = 0.0

    def render_staff(self, staff: StaffSurface, ctx: FrameContext) -> None:
        max_speed = 55.0
        inertia = 0.8
        friction = 3.0
        accel = ctx.imu.ay if ctx.imu.available else 0.0
        slope_ratio = max(min(accel / 9.81, 1.0), -1.0)
        target_speed = max_speed * slope_ratio
        delta = target_speed - self.pace
        rate = inertia if delta > 0 else friction
        self.pace += delta * min(1.0, rate * ctx.dt)

        speed = ctx.settings.speed
        pace_for_frame = self.pace
        if speed.mode == "beat":
            if ctx.beat.just_beat:
                pace_for_frame += 8.0
        else:
            # Apply the speed setting to this frame's movement only.
            # Do not multiply self.pace itself every frame, or Fast/Very Fast grows exponentially.
            pace_for_frame *= float(speed.multiplier or 1.0)

        self.count += pace_for_frame * ctx.dt * 12.0
        palette = ctx.settings.palette
        for depth in range(config.SHAFT_DEPTH):
            color = palette.sample((depth * 2 + self.count) / 255.0, ctx.now * 0.02)
            staff.set_shaft_depth(depth, color)
        staff.fill_top(palette.sample((self.count % 255) / 255.0, ctx.now * 0.02))

    def render_preview(self, staff: StaffSurface, ctx: FrameContext) -> None:
        palette = ctx.settings.palette
        phase = ctx.now * 0.6
        for i in range(config.CONTROL_COUNT):
            staff.set_control(i, palette.sample((i / config.CONTROL_COUNT) + phase, 0))
