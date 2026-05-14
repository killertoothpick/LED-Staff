from __future__ import annotations

from dataclasses import dataclass
from typing import Sequence

from core.colors import Color, sample_palette


@dataclass(frozen=True)
class Palette:
    name: str
    colors: Sequence[Color] | str

    def sample(self, x: float, phase: float = 0.0) -> Color:
        return sample_palette(self.colors, x, phase)


PALETTES: list[Palette] = [
    Palette("Blue Energy", [(33, 77, 255)]),
    Palette("Fire", [(255, 0, 0), (255, 80, 0), (255, 180, 0)]),
    Palette("Ice", [(0, 180, 255), (180, 255, 255), (255, 255, 255)]),
    Palette("Poison", [(0, 255, 80), (120, 0, 255)]),
    Palette("Purple Gold", [(120, 0, 255), (255, 180, 0)]),
    Palette("Rainbow", "rainbow"),
    Palette("White", [(255, 255, 255)]),
]
