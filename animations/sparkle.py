from __future__ import annotations

import random

import config
from animations.base import Animation
from core.colors import BLACK, add_color, scale_color
from core.context import FrameContext
from hardware.leds import StaffSurface


class Sparkle(Animation):
    name = "Sparkle"

    def __init__(self) -> None:
        self.shaft = [BLACK for _ in range(config.SHAFT_DEPTH)]
        self.top = [BLACK for _ in range(config.TOP_COUNT)]
        self.burst = 0.0

    def on_beat(self, ctx: FrameContext) -> None:
        self.burst = 1.0

    def render_staff(self, staff: StaffSurface, ctx: FrameContext) -> None:
        fade = max(0.0, 1.0 - ctx.dt * 3.5)
        self.shaft = [scale_color(c, fade) for c in self.shaft]
        self.top = [scale_color(c, fade) for c in self.top]
        self.burst = max(0.0, self.burst - ctx.dt * 5.0)

        speed_mult = ctx.settings.speed.multiplier or 1.0
        density = 0.8 + ctx.audio.treble * 8.0 + self.burst * 10.0
        if ctx.imu.available:
            density += max(0.0, ctx.imu.motion - 9.8) * 0.15
        if ctx.settings.speed.mode == "fixed":
            density *= speed_mult

        count = max(1, int(density))
        palette = ctx.settings.palette
        for _ in range(count):
            d = random.randrange(config.SHAFT_DEPTH)
            color = palette.sample(random.random(), ctx.now * 0.03)
            self.shaft[d] = add_color(self.shaft[d], color)
        if self.burst > 0:
            for _ in range(6):
                i = random.randrange(config.TOP_COUNT)
                self.top[i] = palette.sample(random.random(), ctx.now * 0.03)

        for depth, color in enumerate(self.shaft):
            staff.set_shaft_depth(depth, color)
        for i, color in enumerate(self.top):
            staff.set_top_pixel(i, color)

    def render_preview(self, staff: StaffSurface, ctx: FrameContext) -> None:
        palette = ctx.settings.palette
        # Random but stable-ish sparkle preview per frame.
        for i in range(config.CONTROL_COUNT):
            if random.random() < 0.12 + ctx.audio.treble * 0.2:
                staff.set_control(i, palette.sample(random.random(), ctx.now * 0.03))
            else:
                staff.set_control(i, scale_color((10, 10, 10), 0.4))
