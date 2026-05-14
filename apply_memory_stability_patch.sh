#!/usr/bin/env bash
set -euo pipefail

cd "${1:-$(pwd)}"

if [[ ! -f main.py || ! -f config.py || ! -d hardware || ! -d core ]]; then
  echo "Run this from the led_staff_v1 project root, or pass the project path as the first argument." >&2
  exit 1
fi

backup_dir="backups/memory_stability_patch_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$backup_dir"
cp -a main.py config.py hardware/leds.py hardware/audio.py hardware/beat.py "$backup_dir"/
[[ -f core/memory.py ]] && cp -a core/memory.py "$backup_dir/memory.py" || true
[[ -f led-staff.service ]] && cp -a led-staff.service "$backup_dir/led-staff.service" || true
[[ -f scripts/install_service.sh ]] && cp -a scripts/install_service.sh "$backup_dir/install_service.sh" || true

echo "Backed up files to $backup_dir"

python - <<'PY'
from pathlib import Path
import re

# ---------------------------------------------------------------------------
# config.py: memory/runtime stability knobs.
# ---------------------------------------------------------------------------
p = Path('config.py')
text = p.read_text()
if 'MEMORY_MAINTENANCE_SEC' not in text:
    text += '''

# Runtime memory stability. The Pi can keep freed C-extension memory in RSS
# unless glibc is asked to trim periodically. This keeps the long-running
# systemd service from slowly drifting into OOM territory.
MEMORY_MAINTENANCE_SEC = float(os.environ.get("LED_STAFF_MEMORY_MAINTENANCE_SEC", "15"))
MEMORY_LOG_SEC = float(os.environ.get("LED_STAFF_MEMORY_LOG_SEC", "60"))
MEMORY_TRIM_ENABLED = os.environ.get("LED_STAFF_MEMORY_TRIM", "1") != "0"
'''
p.write_text(text)

# ---------------------------------------------------------------------------
# hardware/leds.py: stop allocating new pending buffers every frame.
# ---------------------------------------------------------------------------
p = Path('hardware/leds.py')
text = p.read_text()

# Mock fill used during desktop tests.
text = text.replace(
'''    def fill(self, color: Color) -> None:\n        self.buf = [color for _ in range(self.n)]\n''',
'''    def fill(self, color: Color) -> None:\n        for i in range(self.n):\n            self.buf[i] = color\n'''
)

# StaffSurface.clear was allocating two new lists at 60 FPS.
text = text.replace(
'''    def clear(self) -> None:\n        self._main_pending = [BLACK for _ in range(config.MAIN_COUNT)]\n        self._top_pending = [BLACK for _ in range(config.TOP_COUNT)]\n''',
'''    def clear(self) -> None:\n        # Keep the same list objects forever. Reallocating these buffers at\n        # 60 FPS caused allocator/RSS growth on the Pi service.\n        for i in range(len(self._main_pending)):\n            self._main_pending[i] = BLACK\n        for i in range(len(self._top_pending)):\n            self._top_pending[i] = BLACK\n'''
)

# Make sure the confirmed top color order stays fixed if this file still had the old value.
text = text.replace('pixel_order=neopixel.RGB,\n        )\n        return cls(main, top)', 'pixel_order=neopixel.GRB,\n        )\n        return cls(main, top)')
p.write_text(text)

# ---------------------------------------------------------------------------
# hardware/beat.py: update the BeatState object in place instead of allocating
# a new dataclass every frame.
# ---------------------------------------------------------------------------
Path('hardware/beat.py').write_text('''from __future__ import annotations\n\nfrom config import DEFAULT_BPM\nfrom core.context import AudioState, BeatState\n\n\nclass BeatTracker:\n    """Beat-state placeholder with stable phase.\n\n    The aubio-backed tracker will replace these internals in the audio\n    milestone. For now, Beat speed mode behaves like a stable default BPM\n    metronome so animations can already implement beat-aware behavior.\n    """\n\n    def __init__(self, bpm: float = DEFAULT_BPM) -> None:\n        self.state = BeatState(bpm=bpm, bpm_smooth=bpm, beat_interval=60.0 / bpm)\n        self._last_phase_beat = 0.0\n\n    def update(self, now: float, audio: AudioState | None = None) -> BeatState:\n        state = self.state\n        interval = 60.0 / max(1.0, state.bpm_smooth)\n        if state.last_beat_time == 0.0:\n            state.last_beat_time = now\n            self._last_phase_beat = now\n\n        elapsed = now - self._last_phase_beat\n        just = False\n        if elapsed >= interval:\n            missed = int(elapsed // interval)\n            self._last_phase_beat += missed * interval\n            state.last_beat_time = now\n            just = True\n\n        state.just_beat = just\n        state.beat_interval = interval\n        state.phase = min(1.0, max(0.0, (now - self._last_phase_beat) / interval))\n        state.confidence = 0.0\n        return state\n\n    def snapshot(self) -> BeatState:\n        return self.state\n''')

# ---------------------------------------------------------------------------
# hardware/audio.py: avoid per-callback temp arrays/dataclass replacement.
# This matters a lot when sounddevice calls us dozens of times per second.
# ---------------------------------------------------------------------------
Path('hardware/audio.py').write_text('''from __future__ import annotations\n\nimport threading\nimport time\nfrom collections.abc import Callable\n\nimport config\nfrom core.context import AudioState\n\n\nclass AudioProcessor:\n    """Optional live audio state."""\n\n    def __init__(self, logger: Callable[[str], None] | None = None) -> None:\n        self._logger = logger or print\n        self._lock = threading.Lock()\n        self._state = AudioState()\n        self._thread: threading.Thread | None = None\n        self._running = False\n        self._enabled = config.ENABLE_AUDIO and not config.MOCK_HARDWARE\n\n    def start(self) -> None:\n        if not self._enabled:\n            self._logger("Audio disabled; using silent audio state")\n            return\n        self._running = True\n        self._thread = threading.Thread(target=self._run, name="audio", daemon=True)\n        self._thread.start()\n\n    def stop(self) -> None:\n        self._running = False\n        if self._thread:\n            self._thread.join(timeout=1.0)\n\n    def snapshot(self, gain: float = 1.0) -> AudioState:\n        # Return a separate object for the frame, but keep callback state itself\n        # stable/in-place. This is small compared with audio callback churn.\n        with self._lock:\n            base = self._state\n            volume = base.volume\n            volume_smooth = base.volume_smooth\n            bass = base.bass\n            mids = base.mids\n            treble = base.treble\n            clipped = base.clipped\n        return AudioState(\n            volume=min(1.0, volume * gain),\n            volume_smooth=min(1.0, volume_smooth * gain),\n            bass=min(1.0, bass * gain),\n            mids=min(1.0, mids * gain),\n            treble=min(1.0, treble * gain),\n            gain=gain,\n            clipped=clipped,\n        )\n\n    def _run(self) -> None:\n        try:\n            import numpy as np\n            import sounddevice as sd\n        except Exception as exc:\n            self._logger(f"Audio imports failed; continuing without audio: {exc}")\n            return\n\n        def callback(indata, frames, time_info, status):\n            try:\n                # sounddevice gives a float32 ndarray when dtype=\"float32\".\n                # Use views and dot/min/max to avoid allocating samples*samples\n                # or abs(samples) temporary arrays every audio block.\n                samples = indata[:, 0]\n                n = int(samples.size)\n                if n <= 0:\n                    return\n                rms = float((np.dot(samples, samples) / n) ** 0.5)\n                peak = max(float(np.max(samples)), -float(np.min(samples)))\n                clipped = peak > 0.98\n                volume = min(1.0, rms * 12.0)\n                with self._lock:\n                    state = self._state\n                    smooth = state.volume_smooth * 0.85 + volume * 0.15\n                    state.volume = volume\n                    state.volume_smooth = smooth\n                    state.bass = volume\n                    state.mids = volume\n                    state.treble = volume\n                    state.gain = 1.0\n                    state.clipped = clipped\n            except Exception:\n                pass\n\n        while self._running:\n            try:\n                with sd.InputStream(\n                    channels=1,\n                    samplerate=config.AUDIO_SAMPLE_RATE,\n                    blocksize=config.AUDIO_BLOCK_SIZE,\n                    dtype="float32",\n                    callback=callback,\n                ):\n                    self._logger("Audio input initialized")\n                    while self._running:\n                        time.sleep(0.25)\n            except Exception as exc:\n                self._logger(f"Audio input unavailable, retrying: {exc}")\n                time.sleep(2.0)\n''')

# ---------------------------------------------------------------------------
# main.py: call periodic memory maintenance.
# ---------------------------------------------------------------------------
p = Path('main.py')
text = p.read_text()
if 'from core.memory import MemoryMaintenance' not in text:
    text = text.replace('from core.debug import DebugDashboard, RuntimeLog, menu_value_text\n', 'from core.debug import DebugDashboard, RuntimeLog, menu_value_text\nfrom core.memory import MemoryMaintenance\n')
if 'memory = MemoryMaintenance' not in text:
    text = text.replace('    dashboard = DebugDashboard()\n    log.add("LED staff runtime starting")\n', '    dashboard = DebugDashboard()\n    memory = MemoryMaintenance(logger=log.add)\n    log.add("LED staff runtime starting")\n')
if 'memory.tick(frame_start)' not in text:
    marker = '''            dashboard.render(\n                now=frame_start,'''
    idx = text.find(marker)
    if idx == -1:
        raise SystemExit('Could not find dashboard.render block in main.py')
    end_marker = '''            frame += 1\n'''
    end = text.find(end_marker, idx)
    if end == -1:
        raise SystemExit('Could not find frame increment after dashboard.render in main.py')
    text = text[:end] + '            memory.tick(frame_start)\n\n' + text[end:]
p.write_text(text)
PY

cat > core/memory.py <<'PY'
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
PY

# Patch service files if they exist, without requiring them to have a specific shape.
python - <<'PY'
from pathlib import Path

# The checked-in service should run production mode and use fewer glibc arenas.
for p in [Path('led-staff.service')]:
    if not p.exists():
        continue
    text = p.read_text()
    if 'LED_STAFF_DEBUG=' not in text:
        text = text.replace('[Service]\n', '[Service]\nEnvironment=LED_STAFF_DEBUG=0\n', 1)
    else:
        text = text.replace('Environment=LED_STAFF_DEBUG=1', 'Environment=LED_STAFF_DEBUG=0')
    if 'MALLOC_ARENA_MAX=' not in text:
        text = text.replace('[Service]\n', '[Service]\nEnvironment=MALLOC_ARENA_MAX=2\n', 1)
    p.write_text(text)

# Make future installs include the same env if install_service.sh writes a unit.
p = Path('scripts/install_service.sh')
if p.exists():
    text = p.read_text()
    if 'MALLOC_ARENA_MAX=2' not in text:
        text = text.replace('Environment=PYTHONUNBUFFERED=1', 'Environment=PYTHONUNBUFFERED=1\nEnvironment=MALLOC_ARENA_MAX=2\nEnvironment=LED_STAFF_DEBUG=0')
    elif 'LED_STAFF_DEBUG=0' not in text:
        text = text.replace('Environment=MALLOC_ARENA_MAX=2', 'Environment=MALLOC_ARENA_MAX=2\nEnvironment=LED_STAFF_DEBUG=0')
    p.write_text(text)
PY

python -m compileall -q main.py core hardware ui animations

echo "Done. Restart service with:"
echo "  sudo systemctl daemon-reload && sudo systemctl restart led-staff.service"
echo "Watch memory with:"
echo "  watch -n 2 'ps -o pid,etime,%cpu,%mem,rss,vsz,cmd -C python3 -C python | head -20; echo; free -h'"
