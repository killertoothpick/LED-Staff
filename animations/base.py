from __future__ import annotations

from dataclasses import dataclass

import config
from core.colors import BLACK, Color, scale_color
from core.context import FrameContext
from hardware.leds import StaffSurface


class Animation:
    name = "Base"

    def reset(self, ctx: FrameContext) -> None:
        pass

    def on_beat(self, ctx: FrameContext) -> None:
        pass

    def render_staff(self, staff: StaffSurface, ctx: FrameContext) -> None:
        raise NotImplementedError

    def render_preview(self, staff: StaffSurface, ctx: FrameContext) -> None:
        """Render a 16-LED control circle preview."""
        palette = ctx.settings.palette
        for i in range(config.CONTROL_COUNT):
            staff.set_control(i, palette.sample(i / config.CONTROL_COUNT, ctx.now * 0.1))

    def _top_and_shaft_fill(self, staff: StaffSurface, color: Color) -> None:
        staff.fill_top(color)
        staff.fill_shaft(color)
