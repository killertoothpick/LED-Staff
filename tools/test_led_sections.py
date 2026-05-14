from __future__ import annotations

# Allow running this file directly, e.g. `sudo .venv/bin/python tools/test_*.py`.
# Python normally puts tools/ on sys.path, not the project root.
import sys
from pathlib import Path
PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

import time

from core.colors import wheel
from hardware.leds import StaffSurface
import config


def main():
    staff = StaffSurface.create()
    try:
        staff.clear(); staff.show(); time.sleep(0.3)
        print("Top strip")
        staff.clear(); staff.fill_top((0, 0, 40)); staff.show(); time.sleep(1)
        print("Control circle")
        staff.clear(); staff.fill_control((0, 40, 0)); staff.show(); time.sleep(1)
        print("Shaft both sides top to bottom")
        for depth in range(config.SHAFT_DEPTH):
            staff.clear(); staff.set_shaft_depth(depth, (40, 0, 0)); staff.show(); time.sleep(0.015)
        print("Rainbow section test")
        for frame in range(180):
            staff.clear()
            staff.fill_top(wheel(frame * 2))
            for i in range(config.CONTROL_COUNT):
                staff.set_control(i, wheel(i * 16 + frame * 4))
            for d in range(config.SHAFT_DEPTH):
                staff.set_shaft_depth(d, wheel(d * 3 + frame * 2))
            staff.show(); time.sleep(1/60)
    finally:
        staff.clear(); staff.show()

if __name__ == "__main__":
    main()
