#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "main.py" ] || [ ! -d "animations" ]; then
  echo "Run this from the led_staff_v1 project root." >&2
  exit 1
fi

cat > animations/level_stripes.py <<'PY'
from __future__ import annotations

import math

import config
from animations.base import Animation
from core.colors import BLACK, clamp01, scale_color
from core.context import FrameContext
from hardware.leds import StaffSurface


class LevelStripes(Animation):
    """World-level stripe planes using vertical IMU acceleration.

    This effect treats the staff as moving through an infinite stack of
    horizontal colored stripe planes with black space between them. Y is the
    confirmed vertical axis. Raw IMU acceleration is double-integrated into a
    small repeating vertical offset, with deadband + damping to keep inevitable
    IMU drift from running away.
    """

    name = "Level Stripes"

    # Approximate virtual dimensions. These can be tuned after seeing the prop.
    SHAFT_HEIGHT_M = 1.00
    STRIPE_PERIOD_M = 0.16
    COLORED_DUTY = 0.42
    EDGE_SOFTNESS = 0.08

    # Integration stability controls. Raw accel double integration drifts, so
    # the effect intentionally behaves like a visual stabilizer, not a true
    # navigation-grade position tracker.
    GRAVITY_M_S2 = 9.80665
    ACCEL_DEADBAND_M_S2 = 0.22
    VELOCITY_DAMPING_PER_SEC = 1.15
    MAX_VELOCITY_M_S = 1.60
    MAX_FRAME_DT = 0.050

    def __init__(self) -> None:
        self.gravity_y = self.GRAVITY_M_S2
        self.velocity_m_s = 0.0
        self.position_m = 0.0
        self.last_available = False

    def reset(self, ctx: FrameContext) -> None:
        self.velocity_m_s = 0.0
        self.position_m = 0.0
        if ctx.imu.available:
            self.gravity_y = ctx.imu.ay

    def render_staff(self, staff: StaffSurface, ctx: FrameContext) -> None:
        self._update_vertical_offset(ctx)
        palette = ctx.settings.palette

        for depth in range(config.SHAFT_DEPTH):
            height_m = self._height_from_base(depth)
            color = self._stripe_color(palette, height_m, ctx.now)
            staff.set_shaft_depth(depth, color)

        # Let the top show the stripe plane at the top of the shaft so it feels
        # tied into the same infinite world-space pattern.
        top_color = self._stripe_color(ctx.settings.palette, self.SHAFT_HEIGHT_M, ctx.now)
        staff.fill_top(top_color)

    def render_preview(self, staff: StaffSurface, ctx: FrameContext) -> None:
        # A compact preview: alternating colored planes and black gaps around
        # the circle, with the same inertial phase used by the shaft.
        self._update_vertical_offset(ctx)
        palette = ctx.settings.palette
        for i in range(config.CONTROL_COUNT):
            height_m = (i / max(1, config.CONTROL_COUNT - 1)) * self.SHAFT_HEIGHT_M
            color = self._stripe_color(palette, height_m, ctx.now)
            staff.set_control_dial(i, color)

    def _update_vertical_offset(self, ctx: FrameContext) -> None:
        dt = max(0.0, min(self.MAX_FRAME_DT, ctx.dt))
        if not ctx.imu.available:
            # No IMU: slowly settle into a static stripe field.
            self.velocity_m_s *= math.exp(-self.VELOCITY_DAMPING_PER_SEC * dt)
            self.last_available = False
            return

        ay = ctx.imu.ay

        # Re-acquire the resting gravity estimate when the IMU appears. Also
        # slowly bias-correct while motion is low, which reduces long-term drift.
        if not self.last_available:
            self.gravity_y = ay
            self.velocity_m_s = 0.0
            self.last_available = True

        if abs(self.velocity_m_s) < 0.06 and abs(ay - self.gravity_y) < 1.0:
            alpha = min(1.0, dt * 0.45)
            self.gravity_y += (ay - self.gravity_y) * alpha

        vertical_accel = ay - self.gravity_y
        if abs(vertical_accel) < self.ACCEL_DEADBAND_M_S2:
            vertical_accel = 0.0

        self.velocity_m_s += vertical_accel * dt
        self.velocity_m_s = max(-self.MAX_VELOCITY_M_S, min(self.MAX_VELOCITY_M_S, self.velocity_m_s))
        self.velocity_m_s *= math.exp(-self.VELOCITY_DAMPING_PER_SEC * dt)

        self.position_m += self.velocity_m_s * dt

        # Only the stripe phase matters, so wrap to prevent huge floats.
        period = max(0.001, self.STRIPE_PERIOD_M)
        self.position_m = math.fmod(self.position_m, period)

    def _height_from_base(self, surface_depth: int) -> float:
        # StaffSurface depth 0 is top, SHAFT_DEPTH-1 is base.
        if config.SHAFT_DEPTH <= 1:
            return 0.0
        top_to_base = surface_depth / (config.SHAFT_DEPTH - 1)
        return (1.0 - top_to_base) * self.SHAFT_HEIGHT_M

    def _stripe_color(self, palette, height_m: float, now: float):
        world_y = height_m + self.position_m
        period = max(0.001, self.STRIPE_PERIOD_M)
        stripe_float = world_y / period
        phase = stripe_float % 1.0

        if phase >= self.COLORED_DUTY:
            return BLACK

        # Slight antialias/soft edge so the stripes look less jagged while
        # moving, but keep a strong black gap between colored bands.
        edge = min(phase, self.COLORED_DUTY - phase)
        soft = max(0.001, self.EDGE_SOFTNESS)
        intensity = clamp01(edge / soft)

        stripe_index = math.floor(stripe_float)
        # Pick a stable color per stripe, with a tiny time phase so rainbow
        # palettes are alive without sliding the physical stripe planes.
        color = palette.sample((stripe_index * 0.173) % 1.0, now * 0.006)
        return scale_color(color, intensity)
PY

python - <<'PY'
from pathlib import Path

p = Path("animations/__init__.py")
text = p.read_text()

if "from animations.level_stripes import LevelStripes" not in text:
    text = text.replace(
        "from animations.spiral import TiltSpiral\n",
        "from animations.spiral import TiltSpiral\nfrom animations.level_stripes import LevelStripes\n",
    )

if "LevelStripes()," not in text:
    text = text.replace(
        "        TiltSpiral(),\n",
        "        TiltSpiral(),\n        LevelStripes(),\n",
    )

p.write_text(text)
PY

python -m compileall -q animations core hardware ui main.py config.py

echo "Added Level Stripes animation and registered it in animations/build_animations()."
echo "Run: sudo LED_STAFF_AUDIO=1 .venv/bin/python main.py"
