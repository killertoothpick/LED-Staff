from __future__ import annotations

import time

from config import DEFAULT_BPM
from core.context import AudioState, BeatState


class BeatTracker:
    """Beat-state placeholder with stable phase.

    The aubio-backed tracker will replace this internals in the audio milestone.
    For now, Beat speed mode behaves like a stable 120 BPM metronome so animations
    can already implement beat-aware behavior.
    """

    def __init__(self, bpm: float = DEFAULT_BPM) -> None:
        self.state = BeatState(bpm=bpm, bpm_smooth=bpm, beat_interval=60.0 / bpm)
        self._last_phase_beat = 0.0

    def update(self, now: float, audio: AudioState | None = None) -> BeatState:
        interval = 60.0 / max(1.0, self.state.bpm_smooth)
        if self.state.last_beat_time == 0.0:
            self.state.last_beat_time = now
            self._last_phase_beat = now
        elapsed = now - self._last_phase_beat
        just = False
        if elapsed >= interval:
            missed = int(elapsed // interval)
            self._last_phase_beat += missed * interval
            self.state.last_beat_time = now
            just = True
        phase = min(1.0, max(0.0, (now - self._last_phase_beat) / interval))
        self.state = BeatState(
            just_beat=just,
            bpm=self.state.bpm,
            bpm_smooth=self.state.bpm_smooth,
            confidence=0.0,
            last_beat_time=self.state.last_beat_time,
            beat_interval=interval,
            phase=phase,
        )
        return self.state

    def snapshot(self) -> BeatState:
        return self.state
