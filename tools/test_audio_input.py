from __future__ import annotations

# Allow running this file directly, e.g. `sudo .venv/bin/python tools/test_*.py`.
# Python normally puts tools/ on sys.path, not the project root.
import sys
from pathlib import Path
PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

import os
import time

os.environ.setdefault("LED_STAFF_AUDIO", "1")

from hardware.audio import AudioProcessor


def main():
    audio = AudioProcessor()
    audio.start()
    try:
        while True:
            s = audio.snapshot(gain=1.0)
            print(f"vol={s.volume:.3f} smooth={s.volume_smooth:.3f} clipped={s.clipped}")
            time.sleep(0.1)
    finally:
        audio.stop()

if __name__ == "__main__":
    main()
