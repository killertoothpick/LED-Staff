from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Any

from config import DEFAULT_BPM
from core.palettes import PALETTES


@dataclass(frozen=True)
class SpeedOption:
    name: str
    mode: str  # fixed | beat
    multiplier: float | None = None


SPEED_OPTIONS: list[SpeedOption] = [
    SpeedOption("Slow", "fixed", 0.50),
    SpeedOption("Normal", "fixed", 1.00),
    SpeedOption("Fast", "fixed", 2.00),
    SpeedOption("Very Fast", "fixed", 3.00),
    SpeedOption("Beat", "beat", None),
]

BRIGHTNESS_OPTIONS: list[float] = [0.05, 0.10, 0.20, 0.35, 0.50, 0.75, 1.00]
GAIN_OPTIONS: list[float] = [0.50, 0.75, 1.00, 1.50, 2.00, 3.00, 4.00]


@dataclass
class Settings:
    animation_index: int = 0
    palette_index: int = 0
    speed_index: int = 1
    brightness_index: int = 2
    gain_index: int = 2

    def copy(self) -> "Settings":
        return Settings(**asdict(self))

    @property
    def palette(self):
        return PALETTES[self.palette_index % len(PALETTES)]

    @property
    def speed(self) -> SpeedOption:
        return SPEED_OPTIONS[self.speed_index % len(SPEED_OPTIONS)]

    @property
    def brightness(self) -> float:
        return BRIGHTNESS_OPTIONS[self.brightness_index % len(BRIGHTNESS_OPTIONS)]

    @property
    def gain(self) -> float:
        return GAIN_OPTIONS[self.gain_index % len(GAIN_OPTIONS)]

    def to_json(self) -> dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_json(cls, data: dict[str, Any]) -> "Settings":
        s = cls()
        for field in asdict(s):
            if field in data:
                setattr(s, field, int(data[field]))
        s.clamp()
        return s

    def clamp(self, animation_count: int | None = None) -> None:
        if animation_count:
            self.animation_index %= max(1, animation_count)
        self.palette_index %= len(PALETTES)
        self.speed_index %= len(SPEED_OPTIONS)
        self.brightness_index %= len(BRIGHTNESS_OPTIONS)
        self.gain_index %= len(GAIN_OPTIONS)


def speed_step(settings: Settings, dt: float, beat_just_happened: bool, bpm: float = DEFAULT_BPM) -> float:
    """Return animation progress step for the selected speed."""
    option = settings.speed
    if option.mode == "beat":
        if beat_just_happened:
            return 1.0
        # fallback phase drift so beat mode never freezes in silence
        safe_bpm = bpm if bpm > 1 else DEFAULT_BPM
        return dt * (safe_bpm / 60.0)
    return dt * float(option.multiplier or 1.0)
