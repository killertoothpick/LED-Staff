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
        with self._lock:
            s = AudioState(**self._state.__dict__)
        s.gain = gain
        s.volume = min(1.0, s.volume * gain)
        s.volume_smooth = min(1.0, s.volume_smooth * gain)
        s.bass = min(1.0, s.bass * gain)
        s.mids = min(1.0, s.mids * gain)
        s.treble = min(1.0, s.treble * gain)
        return s

    def _run(self) -> None:
        try:
            import numpy as np
            import sounddevice as sd
        except Exception as exc:
            self._logger(f"Audio imports failed; continuing without audio: {exc}")
            return

        def callback(indata, frames, time_info, status):
            try:
                samples = np.asarray(indata[:, 0], dtype=np.float32)
                rms = float(np.sqrt(np.mean(samples * samples)))
                clipped = bool(np.max(np.abs(samples)) > 0.98)
                volume = min(1.0, rms * 12.0)
                with self._lock:
                    prev = self._state.volume_smooth
                    smooth = prev * 0.85 + volume * 0.15
                    self._state = AudioState(
                        volume=volume,
                        volume_smooth=smooth,
                        bass=volume,
                        mids=volume,
                        treble=volume,
                        gain=1.0,
                        clipped=clipped,
                    )
            except Exception:
                pass

        while self._running:
            try:
                with sd.InputStream(
                    channels=1,
                    samplerate=config.AUDIO_SAMPLE_RATE,
                    blocksize=config.AUDIO_BLOCK_SIZE,
                    callback=callback,
                ):
                    self._logger("Audio input initialized")
                    while self._running:
                        time.sleep(0.25)
            except Exception as exc:
                self._logger(f"Audio input unavailable, retrying: {exc}")
                time.sleep(2.0)
