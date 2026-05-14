#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "main.py" ] || [ ! -d "animations" ] || [ ! -d "core" ]; then
  echo "Run this from the led_staff_v1 project root." >&2
  exit 1
fi

cat > animations/level_stripes.py <<'PY'
from __future__ import annotations

import math
from typing import Tuple

import config
from animations.base import Animation
from core.colors import BLACK, clamp01, scale_color
from core.context import FrameContext
from hardware.leds import StaffSurface

Vec3 = Tuple[float, float, float]


class LevelStripes(Animation):
    """World-level horizontal stripe planes using full X/Y/Z IMU tilt.

    The shaft is treated as moving through an infinite stack of horizontal
    stripe planes. The key difference from a simple Y-only effect is that this
    animation estimates the world-up direction from the accelerometer's gravity
    vector and projects both the shaft's local +Y axis and the linear
    acceleration onto that world-up vector.

    Confirmed staff axes:
      +Y = base-to-top / up when held upright
      +X = right
      +Z = remaining perpendicular axis

    This is still a visual inertial stabilizer, not true dead-reckoning. A raw
    accelerometer cannot perfectly separate tilt, gravity, and translation, so
    damping/deadband are intentionally used to keep the visual stable.
    """

    name = "Level Stripes"

    # Approximate virtual dimensions. Tune SHAFT_HEIGHT_M and STRIPE_PERIOD_M
    # after seeing the stripe scale on the real prop.
    SHAFT_HEIGHT_M = 1.00
    STRIPE_PERIOD_M = 0.16
    COLORED_DUTY = 0.42
    EDGE_SOFTNESS = 0.08

    # +Y is the staff's local base-to-top axis.
    LOCAL_UP_AXIS: Vec3 = (0.0, 1.0, 0.0)

    GRAVITY_M_S2 = 9.80665
    ACCEL_DEADBAND_M_S2 = 0.18
    VELOCITY_DAMPING_PER_SEC = 1.10
    MAX_VELOCITY_M_S = 1.50
    MAX_FRAME_DT = 0.050

    # How quickly the gravity vector follows tilt changes. Higher = tracks tilt
    # faster, lower = less pollution from linear movement.
    GRAVITY_TRACK_PER_SEC = 2.4

    # If the inertial compensation feels backwards on the real staff, change
    # this to -1.0. The code auto-calibrates gravity sign at rest, so this
    # should normally stay +1.0.
    ACCEL_SIGN = 1.0

    def __init__(self) -> None:
        # Start with the user's confirmed convention: Y is up.
        self.gravity: Vec3 = (0.0, self.GRAVITY_M_S2, 0.0)
        self.world_up_sign = 1.0
        self.velocity_m_s = 0.0
        self.position_m = 0.0
        self.last_available = False

    def reset(self, ctx: FrameContext) -> None:
        self.velocity_m_s = 0.0
        self.position_m = 0.0
        self.last_available = False
        if ctx.imu.available:
            self._recalibrate_from_sample((ctx.imu.ax, ctx.imu.ay, ctx.imu.az))

    def render_staff(self, staff: StaffSurface, ctx: FrameContext) -> None:
        world_up = self._update_world_motion(ctx)
        palette = ctx.settings.palette

        # Dot(local shaft axis, world up) gives how much a base-to-top step on
        # the staff changes world height. Upright ~= 1, horizontal ~= 0,
        # upside-down ~= -1. This is what accounts for X and Z tilt.
        shaft_vertical_factor = self._dot(self.LOCAL_UP_AXIS, world_up)

        for depth in range(config.SHAFT_DEPTH):
            local_height_m = self._height_from_base(depth)
            world_height_m = local_height_m * shaft_vertical_factor
            color = self._stripe_color(palette, world_height_m, ctx.now)
            staff.set_shaft_depth(depth, color)

        top_world_height_m = self.SHAFT_HEIGHT_M * shaft_vertical_factor
        staff.fill_top(self._stripe_color(palette, top_world_height_m, ctx.now))

    def render_preview(self, staff: StaffSurface, ctx: FrameContext) -> None:
        world_up = self._update_world_motion(ctx)
        shaft_vertical_factor = self._dot(self.LOCAL_UP_AXIS, world_up)
        palette = ctx.settings.palette

        for i in range(config.CONTROL_COUNT):
            local_height_m = (i / max(1, config.CONTROL_COUNT - 1)) * self.SHAFT_HEIGHT_M
            color = self._stripe_color(palette, local_height_m * shaft_vertical_factor, ctx.now)
            # Newer patches provide set_control_dial() for clockwise/right-side
            # UI semantics. Older code only has set_control(). Support both so
            # this patch works against the old zip too.
            if hasattr(staff, "set_control_dial"):
                staff.set_control_dial(i, color)
            else:
                staff.set_control(i, color)

    def _update_world_motion(self, ctx: FrameContext) -> Vec3:
        dt = max(0.0, min(self.MAX_FRAME_DT, ctx.dt))
        if not ctx.imu.available:
            self.velocity_m_s *= math.exp(-self.VELOCITY_DAMPING_PER_SEC * dt)
            self.last_available = False
            return self._world_up_unit()

        sample = (ctx.imu.ax, ctx.imu.ay, ctx.imu.az)

        if not self.last_available:
            self._recalibrate_from_sample(sample)
            self.last_available = True
            return self._world_up_unit()

        # Low-pass the full 3D acceleration vector to estimate gravity/tilt.
        # This lets X/Z tilt rotate the world-up vector instead of assuming raw
        # sensor Y is always vertical.
        alpha = 1.0 - math.exp(-self.GRAVITY_TRACK_PER_SEC * dt)
        self.gravity = self._lerp_vec(self.gravity, sample, clamp01(alpha))

        world_up = self._world_up_unit()
        linear = self._sub(sample, self.gravity)
        vertical_accel = self.ACCEL_SIGN * self._dot(linear, world_up)

        if abs(vertical_accel) < self.ACCEL_DEADBAND_M_S2:
            vertical_accel = 0.0

        self.velocity_m_s += vertical_accel * dt
        self.velocity_m_s = max(-self.MAX_VELOCITY_M_S, min(self.MAX_VELOCITY_M_S, self.velocity_m_s))
        self.velocity_m_s *= math.exp(-self.VELOCITY_DAMPING_PER_SEC * dt)

        self.position_m += self.velocity_m_s * dt

        # Only repeating stripe phase matters. Keep position bounded.
        period = max(0.001, self.STRIPE_PERIOD_M)
        self.position_m = math.fmod(self.position_m, period)
        return world_up

    def _recalibrate_from_sample(self, sample: Vec3) -> None:
        if self._norm(sample) < 0.1:
            sample = (0.0, self.GRAVITY_M_S2, 0.0)
        self.gravity = sample

        # Some IMUs report +g on the upward axis at rest, others report -g.
        # Pick the sign that makes world-up align with local +Y when the staff
        # is upright, based on the current resting sample.
        g_unit = self._unit(self.gravity, (0.0, 1.0, 0.0))
        self.world_up_sign = 1.0 if self._dot(self.LOCAL_UP_AXIS, g_unit) >= 0.0 else -1.0

    def _world_up_unit(self) -> Vec3:
        g_unit = self._unit(self.gravity, (0.0, 1.0, 0.0))
        return self._scale(g_unit, self.world_up_sign)

    def _height_from_base(self, surface_depth: int) -> float:
        # StaffSurface depth 0 is top, SHAFT_DEPTH-1 is base.
        if config.SHAFT_DEPTH <= 1:
            return 0.0
        top_to_base = surface_depth / (config.SHAFT_DEPTH - 1)
        return (1.0 - top_to_base) * self.SHAFT_HEIGHT_M

    def _stripe_color(self, palette, world_height_m: float, now: float):
        world_y = world_height_m + self.position_m
        period = max(0.001, self.STRIPE_PERIOD_M)
        stripe_float = world_y / period
        phase = stripe_float % 1.0

        if phase >= self.COLORED_DUTY:
            return BLACK

        edge = min(phase, self.COLORED_DUTY - phase)
        soft = max(0.001, self.EDGE_SOFTNESS)
        intensity = clamp01(edge / soft)

        stripe_index = math.floor(stripe_float)
        color = palette.sample((stripe_index * 0.173) % 1.0, now * 0.006)
        return scale_color(color, intensity)

    @staticmethod
    def _dot(a: Vec3, b: Vec3) -> float:
        return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]

    @staticmethod
    def _norm(v: Vec3) -> float:
        return math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])

    @classmethod
    def _unit(cls, v: Vec3, fallback: Vec3) -> Vec3:
        n = cls._norm(v)
        if n < 1e-6:
            return fallback
        return (v[0] / n, v[1] / n, v[2] / n)

    @staticmethod
    def _scale(v: Vec3, s: float) -> Vec3:
        return (v[0] * s, v[1] * s, v[2] * s)

    @staticmethod
    def _sub(a: Vec3, b: Vec3) -> Vec3:
        return (a[0] - b[0], a[1] - b[1], a[2] - b[2])

    @staticmethod
    def _lerp_vec(a: Vec3, b: Vec3, t: float) -> Vec3:
        return (
            a[0] + (b[0] - a[0]) * t,
            a[1] + (b[1] - a[1]) * t,
            a[2] + (b[2] - a[2]) * t,
        )
PY

python - <<'PY'
from pathlib import Path
import re

p = Path("animations/__init__.py")
text = p.read_text()

if "from animations.level_stripes import LevelStripes" not in text:
    # Prefer placing it after TiltSpiral if that exists.
    if "from animations.spiral import TiltSpiral\n" in text:
        text = text.replace(
            "from animations.spiral import TiltSpiral\n",
            "from animations.spiral import TiltSpiral\nfrom animations.level_stripes import LevelStripes\n",
        )
    else:
        text += "\nfrom animations.level_stripes import LevelStripes\n"

if "LevelStripes()," not in text:
    if "TiltSpiral()," in text:
        text = text.replace("TiltSpiral(),", "TiltSpiral(),\n        LevelStripes(),")
    else:
        # Insert before the final closing bracket of build_animations().
        text = re.sub(r"(return\s*\[[\s\S]*?)(\n\s*\])", r"\1\n        LevelStripes(),\2", text, count=1)

p.write_text(text)
PY

python - <<'PY'
from pathlib import Path

# Align the default IMUState with the confirmed physical convention: Y is up.
p = Path("core/context.py")
if p.exists():
    text = p.read_text()
    text = text.replace("ax: float = 0.0\n    ay: float = 0.0\n    az: float = 9.80665", "ax: float = 0.0\n    ay: float = 9.80665\n    az: float = 0.0")
    p.write_text(text)
PY

python -m compileall -q animations core hardware ui main.py config.py

echo "Updated Level Stripes to use full X/Y/Z tilt compensation."
echo "Run: sudo LED_STAFF_AUDIO=1 .venv/bin/python main.py"
