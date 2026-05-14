from __future__ import annotations

from typing import Iterable, Sequence, Tuple

Color = Tuple[int, int, int]
BLACK: Color = (0, 0, 0)
WHITE: Color = (255, 255, 255)


def clamp8(value: float | int) -> int:
    return 0 if value < 0 else 255 if value > 255 else int(value)


def clamp01(value: float) -> float:
    return 0.0 if value < 0 else 1.0 if value > 1 else float(value)


def scale_color(color: Color, scale: float) -> Color:
    scale = max(0.0, scale)
    return (clamp8(color[0] * scale), clamp8(color[1] * scale), clamp8(color[2] * scale))


def add_color(a: Color, b: Color) -> Color:
    return (clamp8(a[0] + b[0]), clamp8(a[1] + b[1]), clamp8(a[2] + b[2]))


def blend(a: Color, b: Color, t: float) -> Color:
    t = clamp01(t)
    return (
        clamp8(a[0] + (b[0] - a[0]) * t),
        clamp8(a[1] + (b[1] - a[1]) * t),
        clamp8(a[2] + (b[2] - a[2]) * t),
    )


def wheel(pos: int | float) -> Color:
    """Rainbow wheel compatible with the old staff script."""
    pos = int(pos) % 256
    if pos < 85:
        return (pos * 3, 255 - pos * 3, 0)
    if pos < 170:
        pos -= 85
        return (255 - pos * 3, 0, pos * 3)
    pos -= 170
    return (0, pos * 3, 255 - pos * 3)


def sample_palette(colors: Sequence[Color] | str, x: float, phase: float = 0.0) -> Color:
    """Sample a palette at position x in [0, 1]."""
    if colors == "rainbow":
        return wheel((x + phase) * 255)
    if not colors:
        return WHITE
    if len(colors) == 1:
        return colors[0]
    x = (x + phase) % 1.0
    scaled = x * len(colors)
    i = int(scaled) % len(colors)
    j = (i + 1) % len(colors)
    t = scaled - int(scaled)
    return blend(colors[i], colors[j], t)


def average_color(colors: Sequence[Color] | str, phase: float = 0.0) -> Color:
    if colors == "rainbow":
        return wheel(phase * 255)
    if not colors:
        return WHITE
    r = sum(c[0] for c in colors) / len(colors)
    g = sum(c[1] for c in colors) / len(colors)
    b = sum(c[2] for c in colors) / len(colors)
    return (clamp8(r), clamp8(g), clamp8(b))
