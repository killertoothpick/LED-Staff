from __future__ import annotations

from typing import Iterable

import config
from core.colors import BLACK, Color, scale_color


class MockNeoPixel:
    def __init__(self, pin, n: int, brightness: float = 1.0, auto_write: bool = False, pixel_order=None):
        self.pin = pin
        self.n = n
        self.brightness = brightness
        self.auto_write = auto_write
        self.pixel_order = pixel_order
        self.buf = [BLACK for _ in range(n)]

    def __len__(self) -> int:
        return self.n

    def __setitem__(self, index: int, color: Color) -> None:
        if 0 <= index < self.n:
            self.buf[index] = color

    def __getitem__(self, index: int) -> Color:
        return self.buf[index]

    def fill(self, color: Color) -> None:
        self.buf = [color for _ in range(self.n)]

    def show(self) -> None:
        pass


class StaffSurface:
    """Logical drawing surface for the LED staff.

    The top now has 7 logical LEDs. The two physical 7-LED top strands mirror
    the same data, so setting top logical LED 3 lights LED 3 on both strands.
    """

    def __init__(self, main_pixels, top_pixels):
        self.main = main_pixels
        self.top = top_pixels
        self.output_scale = 1.0
        self._main_pending = [BLACK for _ in range(config.MAIN_COUNT)]
        self._top_pending = [BLACK for _ in range(config.TOP_COUNT)]

        self.right_down = list(range(config.SHAFT_RIGHT_START, config.SHAFT_RIGHT_END + 1))
        self.left_up = list(range(config.SHAFT_LEFT_START, config.SHAFT_LEFT_END + 1))
        self.left_down = list(reversed(self.left_up))

    @classmethod
    def create(cls) -> "StaffSurface":
        if config.MOCK_HARDWARE:
            return cls(MockNeoPixel(config.MAIN_PIXEL_PIN, config.MAIN_COUNT), MockNeoPixel(config.TOP_PIXEL_PIN, config.TOP_COUNT))

        import board
        import neopixel

        main_pin = getattr(board, config.MAIN_PIXEL_PIN)
        top_pin = getattr(board, config.TOP_PIXEL_PIN)

        main = neopixel.NeoPixel(
            main_pin,
            config.MAIN_COUNT,
            brightness=config.DEFAULT_MAIN_BRIGHTNESS,
            auto_write=False,
            pixel_order=neopixel.GRB,
        )
        top = neopixel.NeoPixel(
            top_pin,
            config.TOP_COUNT,
            brightness=config.DEFAULT_TOP_BRIGHTNESS,
            auto_write=False,
            pixel_order=neopixel.GRB,
        )
        return cls(main, top)

    def set_output_scale(self, scale: float) -> None:
        self.output_scale = max(0.0, min(config.MAX_OUTPUT_SCALE, scale))

    def clear(self) -> None:
        self._main_pending = [BLACK for _ in range(config.MAIN_COUNT)]
        self._top_pending = [BLACK for _ in range(config.TOP_COUNT)]

    def fill_all(self, color: Color) -> None:
        self.fill_top(color)
        self.fill_control(color)
        self.fill_shaft(color)

    def set_main_raw(self, index: int, color: Color) -> None:
        if 0 <= index < config.MAIN_COUNT:
            self._main_pending[index] = color

    def set_top_pixel(self, index: int, color: Color) -> None:
        """Set one logical top LED.

        Hardware mirrors each logical top LED onto both physical top strands.
        """
        if 0 <= index < config.TOP_COUNT:
            self._top_pending[index] = color

    def fill_top(self, color: Color) -> None:
        for i in range(config.TOP_COUNT):
            self._top_pending[i] = color

    def fill_top_shared_side(self, color: Color) -> None:
        for i in range(min(config.TOP_TRIANGLE_SHARED_COUNT, config.TOP_COUNT)):
            self.set_top_pixel(i, color)

    def fill_top_branch_sides(self, color: Color) -> None:
        for i in range(config.TOP_TRIANGLE_SHARED_COUNT, config.TOP_COUNT):
            self.set_top_pixel(i, color)

    def set_control(self, index: int, color: Color) -> None:
        if 0 <= index < config.CONTROL_COUNT:
            self._main_pending[config.CONTROL_START + index] = color

    def control_dial_index(self, step: int | float) -> int:
        """Map logical clockwise dial steps to the physical control-ring index."""
        step_i = int(round(step))
        return (config.CONTROL_DIAL_ZERO + config.CONTROL_DIAL_CLOCKWISE * step_i) % config.CONTROL_COUNT

    def set_control_dial(self, step: int | float, color: Color) -> None:
        self.set_control(self.control_dial_index(step), color)

    def fill_control(self, color: Color) -> None:
        for i in range(config.CONTROL_COUNT):
            self.set_control(i, color)

    def set_control_ring(self, colors: Iterable[Color]) -> None:
        for i, color in enumerate(colors):
            if i >= config.CONTROL_COUNT:
                break
            self.set_control(i, color)

    def fill_shaft(self, color: Color) -> None:
        for idx in self.right_down:
            self._main_pending[idx] = color
        for idx in self.left_up:
            self._main_pending[idx] = color

    def set_shaft_depth(self, depth: int | float, color: Color) -> None:
        """Set both shaft sides at a visual top-to-bottom depth."""
        depth_i = int(round(depth))
        if not (0 <= depth_i < config.SHAFT_DEPTH):
            return
        ri = self._scaled_index(depth_i, config.SHAFT_DEPTH, len(self.right_down))
        li = self._scaled_index(depth_i, config.SHAFT_DEPTH, len(self.left_down))
        self._main_pending[self.right_down[ri]] = color
        self._main_pending[self.left_down[li]] = color

    def set_shaft_side_depth(self, side: str, depth: int | float, color: Color) -> None:
        depth_i = int(round(depth))
        if not (0 <= depth_i < config.SHAFT_DEPTH):
            return
        side = side.lower()
        if side.startswith("r"):
            ri = self._scaled_index(depth_i, config.SHAFT_DEPTH, len(self.right_down))
            self._main_pending[self.right_down[ri]] = color
        elif side.startswith("l"):
            li = self._scaled_index(depth_i, config.SHAFT_DEPTH, len(self.left_down))
            self._main_pending[self.left_down[li]] = color

    def set_shaft_sides(self, depth: int | float, right_color: Color, left_color: Color) -> None:
        self.set_shaft_side_depth("right", depth, right_color)
        self.set_shaft_side_depth("left", depth, left_color)

    def show(self) -> None:
        scale = self.output_scale
        for i, color in enumerate(self._main_pending):
            self.main[i] = scale_color(color, scale)
        for i, color in enumerate(self._top_pending):
            self.top[i] = scale_color(color, scale)
        self.main.show()
        self.top.show()

    @staticmethod
    def _scaled_index(depth: int, depth_count: int, physical_count: int) -> int:
        if physical_count <= 1:
            return 0
        if depth_count <= 1:
            return 0
        return max(0, min(physical_count - 1, round(depth * (physical_count - 1) / (depth_count - 1))))


def boot_animation(staff: StaffSurface, duration: float = 1.15) -> None:
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
