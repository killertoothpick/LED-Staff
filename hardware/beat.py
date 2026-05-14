from __future__ import annotations

from config import DEFAULT_BPM
from core.context import AudioState, BeatState


class BeatTracker:
    """Beat-state placeholder with stable phase.

    The aubio-backed tracker will replace these internals in the audio
    milestone. For now, Beat speed mode behaves like a stable default BPM
    metronome so animations can already implement beat-aware behavior.
    """

    def __init__(self, bpm: float = DEFAULT_BPM) -> None:
        self.state = BeatState(bpm=bpm, bpm_smooth=bpm, beat_interval=60.0 / bpm)
        self._last_phase_beat = 0.0

    def update(self, now: float, audio: AudioState | None = None) -> BeatState:
        state = self.state
        interval = 60.0 / max(1.0, state.bpm_smooth)
        if state.last_beat_time == 0.0:
            state.last_beat_time = now
            self._last_phase_beat = now

        elapsed = now - self._last_phase_beat
        just = False
        if elapsed >= interval:
            missed = int(elapsed // interval)
            self._last_phase_beat += missed * interval
            state.last_beat_time = now
            just = True

        state.just_beat = just
        state.beat_interval = interval
        state.phase = min(1.0, max(0.0, (now - self._last_phase_beat) / interval))
        state.confidence = 0.0
        return state

    def snapshot(self) -> BeatState:
        return self.state
