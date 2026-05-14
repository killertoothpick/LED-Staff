from __future__ import annotations

import threading
import time
from collections.abc import Callable

import config
from core.context import AudioState


class AudioProcessor:
    """Optional live audio state."""

    def __init__(self, logger: Callable[[str], None] | None = None) -> None:
        self._logger = logger or print
        self._lock = threading.Lock()
        self._state = AudioState()
        self._thread: threading.Thread | None = None
        self._running = False
        self._enabled = config.ENABLE_AUDIO and not config.MOCK_HARDWARE

    def start(self) -> None:
        if not self._enabled:
            self._logger("Audio disabled; using silent audio state")
            return
        self._running = True
        self._thread = threading.Thread(target=self._run, name="audio", daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._running = False
        if self._thread:
            self._thread.join(timeout=1.0)

    def snapshot(self, gain: float = 1.0) -> AudioState:
        # Return a separate object for the frame, but keep callback state itself
        # stable/in-place. This is small compared with audio callback churn.
        with self._lock:
            base = self._state
            volume = base.volume
            volume_smooth = base.volume_smooth
            bass = base.bass
            mids = base.mids
            treble = base.treble
            clipped = base.clipped
        return AudioState(
            volume=min(1.0, volume * gain),
            volume_smooth=min(1.0, volume_smooth * gain),
            bass=min(1.0, bass * gain),
            mids=min(1.0, mids * gain),
            treble=min(1.0, treble * gain),
            gain=gain,
            clipped=clipped,
        )

    def _run(self) -> None:
        try:
            import numpy as np
            import sounddevice as sd
        except Exception as exc:
            self._logger(f"Audio imports failed; continuing without audio: {exc}")
            return

        def callback(indata, frames, time_info, status):
            try:
                # sounddevice gives a float32 ndarray when dtype="float32".
                # Use views and dot/min/max to avoid allocating samples*samples
                # or abs(samples) temporary arrays every audio block.
                samples = indata[:, 0]
                n = int(samples.size)
                if n <= 0:
                    return
                rms = float((np.dot(samples, samples) / n) ** 0.5)
                peak = max(float(np.max(samples)), -float(np.min(samples)))
                clipped = peak > 0.98
                volume = min(1.0, rms * 12.0)
                with self._lock:
                    state = self._state
                    smooth = state.volume_smooth * 0.85 + volume * 0.15
                    state.volume = volume
                    state.volume_smooth = smooth
                    state.bass = volume
                    state.mids = volume
                    state.treble = volume
                    state.gain = 1.0
                    state.clipped = clipped
            except Exception:
                pass

        while self._running:
            try:
                with sd.InputStream(
                    channels=1,
                    samplerate=config.AUDIO_SAMPLE_RATE,
                    blocksize=config.AUDIO_BLOCK_SIZE,
                    dtype="float32",
                    callback=callback,
                ):
                    self._logger("Audio input initialized")
                    while self._running:
                        time.sleep(0.25)
            except Exception as exc:
                self._logger(f"Audio input unavailable, retrying: {exc}")
                time.sleep(2.0)
