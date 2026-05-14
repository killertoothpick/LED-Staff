from __future__ import annotations

import math

import config
from animations.base import Animation
from core.colors import clamp8, scale_color
from core.context import FrameContext
from hardware.leds import StaffSurface


class AccelRGB(Animation):
    name = "Accel RGB"

    def __init__(self) -> None:
        self.last_brightness = 0.0

    def render_staff(self, staff: StaffSurface, ctx: FrameContext) -> None:
        max_accel = 10.0
        gravity = 9.80665
        ax, ay, az = ctx.imu.ax, ctx.imu.ay, ctx.imu.az
        ay_corrected = ay - gravity
        ax = max(min(ax, max_accel), -max_accel)
        ay_corrected = max(min(ay_corrected, max_accel), -max_accel)
        az = max(min(az, max_accel), -max_accel)

        scale = 255 / max_accel
        r = clamp8(abs(ay_corrected) * scale)
        g = clamp8(abs(az) * scale)
        b = clamp8(abs(ax) * scale)

        motion = math.sqrt(ax * ax + ay_corrected * ay_corrected + az * az)
        if motion > self.last_brightness:
            self.last_brightness = motion
        self.last_brightness = max(0.0, self.last_brightness - 2.0 * ctx.dt)
        brightness_factor = min(self.last_brightness / max_accel, 1.0)

        # Audio adds a subtle lift; beat gives a brief punch.
        brightness_factor = min(1.0, brightness_factor + ctx.audio.volume_smooth * 0.35)
        if ctx.beat.just_beat:
            brightness_factor = min(1.0, brightness_factor + 0.25)

        color = (int(r * brightness_factor), int(g * brightness_factor), int(b * brightness_factor))
        staff.fill_top(color)
        staff.fill_shaft(color)

    def render_preview(self, staff: StaffSurface, ctx: FrameContext) -> None:
        phase = ctx.now * 0.4
        for i in range(config.CONTROL_COUNT):
            color = (
                clamp8(120 + 120 * math.sin(phase + i * 0.4)),
                clamp8(120 + 120 * math.sin(phase + i * 0.4 + 2.0)),
                clamp8(120 + 120 * math.sin(phase + i * 0.4 + 4.0)),
            )
            staff.set_control(i, color)
