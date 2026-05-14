from __future__ import annotations

# Allow running this file directly, e.g. `sudo .venv/bin/python tools/test_*.py`.
# Python normally puts tools/ on sys.path, not the project root.
import sys
from pathlib import Path
PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

import time

from hardware.imu import IMUReader


def main():
    imu = IMUReader()
    while True:
        s = imu.update()
        print(f"available={s.available} ax={s.ax:.2f} ay={s.ay:.2f} az={s.az:.2f} motion={s.motion:.2f} tilt=({s.tilt_x:.2f}, {s.tilt_y:.2f})")
        time.sleep(0.1)

if __name__ == "__main__":
    main()
