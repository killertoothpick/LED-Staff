from __future__ import annotations

import time


class FPSCounter:
    def __init__(self, interval: float = 5.0) -> None:
        self.interval = interval
        self.last_report = time.monotonic()
        self.frames = 0
        self.last_fps = 0.0

    def tick(self, now: float) -> float | None:
        self.frames += 1
        elapsed = now - self.last_report
        if elapsed >= self.interval:
            self.last_fps = self.frames / elapsed
            self.frames = 0
            self.last_report = now
            return self.last_fps
        return None
