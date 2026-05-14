from __future__ import annotations

import ctypes
import gc
import os
import sys
from collections.abc import Callable

import config


class MemoryMaintenance:
    """Periodic GC + glibc malloc_trim for long-running Pi service.

    The runtime does a lot of small per-frame work and also uses C extensions
    for audio/LED I/O. On Linux, freed native memory may remain in process RSS
    indefinitely unless glibc is asked to trim. This class keeps RSS bounded and
    logs enough to confirm whether memory is stable.
    """

    def __init__(self, logger: Callable[[str], None] | None = None) -> None:
        self._logger = logger or print
        self._next_maintenance_at = 0.0
        self._next_log_at = 0.0
        self._libc = None
        if getattr(config, "MEMORY_TRIM_ENABLED", True) and sys.platform.startswith("linux"):
            try:
                self._libc = ctypes.CDLL("libc.so.6")
                self._libc.malloc_trim.argtypes = [ctypes.c_size_t]
                self._libc.malloc_trim.restype = ctypes.c_int
            except Exception:
                self._libc = None

    def tick(self, now: float) -> None:
        if now < self._next_maintenance_at:
            return
        self._next_maintenance_at = now + max(1.0, float(getattr(config, "MEMORY_MAINTENANCE_SEC", 15.0)))

        before = self.rss_kb()
        # Full collection is cheap at this cadence and helps clear cycles from
        # libraries before asking glibc to return free arenas to the OS.
        gc.collect()
        if self._libc is not None:
            try:
                self._libc.malloc_trim(0)
            except Exception:
                pass
        after = self.rss_kb()

        log_interval = max(5.0, float(getattr(config, "MEMORY_LOG_SEC", 60.0)))
        if now >= self._next_log_at:
            self._next_log_at = now + log_interval
            if before and after:
                self._logger(f"memory rss={after / 1024:.1f} MiB after maintenance; before={before / 1024:.1f} MiB")
            elif after:
                self._logger(f"memory rss={after / 1024:.1f} MiB after maintenance")

    @staticmethod
    def rss_kb() -> int:
        try:
            with open("/proc/self/status", "r", encoding="utf-8") as f:
                for line in f:
                    if line.startswith("VmRSS:"):
                        parts = line.split()
                        return int(parts[1])
        except Exception:
            return 0
        return 0
