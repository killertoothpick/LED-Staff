from __future__ import annotations

from dataclasses import dataclass, replace

from core.settings import Settings


@dataclass
class AudioState:
    volume: float = 0.0
    volume_smooth: float = 0.0
    bass: float = 0.0
    mids: float = 0.0
    treble: float = 0.0
    gain: float = 1.0
    clipped: bool = False


@dataclass
class BeatState:
    just_beat: bool = False
    bpm: float = 120.0
    bpm_smooth: float = 120.0
    confidence: float = 0.0
    last_beat_time: float = 0.0
    beat_interval: float = 0.5
    phase: float = 0.0


@dataclass
class IMUState:
    ax: float = 0.0
    ay: float = 9.80665
    az: float = 0.0
    gx: float = 0.0
    gy: float = 0.0
    gz: float = 0.0
    motion: float = 0.0
    tilt_x: float = 0.0
    tilt_y: float = 0.0
    tilt_angle: float = 0.0
    available: bool = False


@dataclass
class FrameContext:
    now: float
    dt: float
    frame: int
    settings: Settings
    beat: BeatState
    imu: IMUState
    audio: AudioState

    def with_settings(self, settings: Settings) -> "FrameContext":
        return replace(self, settings=settings)
