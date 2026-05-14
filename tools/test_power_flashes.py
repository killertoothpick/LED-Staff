#!/usr/bin/env python3
from __future__ import annotations

# Allow running this file directly, e.g.
# sudo .venv/bin/python tools/test_power_flashes.py
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

import time

from hardware.leds import StaffSurface
import config


FLASH_MS = 100
OFF_PAUSE_MS = 700


def brightness_steps_16():
    """
    16 flashes total.

    True doubling with 8-bit LEDs cannot produce 16 distinct visible values
    between 0 and 255, so this uses fractional doubling internally and rounds
    to 8-bit RGB values.

    The last flashes are the important high-current ones.
    """
    steps = [0]

    for i in range(1, 16):
        value = round(255 * (2 ** (i - 15)))
        steps.append(value)

    return steps


def fill_full_staff(staff: StaffSurface, rgb: tuple[int, int, int]) -> None:
    """
    Fill the entire logical staff:
    - top strip
    - control circle
    - shaft, both sides, full depth
    """
    staff.fill_top(rgb)
    staff.fill_control(rgb)

    for depth in range(config.SHAFT_DEPTH):
        staff.set_shaft_depth(depth, rgb)


def main():
    staff = StaffSurface.create()

    print("FULL STAFF POWER FLASH TEST")
    print("Using StaffSurface.create(), so this uses the same known-good pins/config as test_led_sections.py")
    print()
    print("All LEDs will flash white for 100ms.")
    print("Ctrl+C to stop.")
    print()

    try:
        staff.clear()
        staff.show()
        time.sleep(0.3)

        steps = brightness_steps_16()

        for flash_num, value in enumerate(steps, start=1):
            percent = value / 255 * 100
            rgb = (value, value, value)

            print(
                f"Flash {flash_num:02d}/16 | "
                f"brightness={percent:7.3f}% | "
                f"RGB={rgb}",
                flush=True,
            )

            staff.clear()
            fill_full_staff(staff, rgb)
            staff.show()

            time.sleep(FLASH_MS / 1000)

            staff.clear()
            staff.show()

            time.sleep(OFF_PAUSE_MS / 1000)

        print()
        print("Full staff power flash test complete.")

    except KeyboardInterrupt:
        print()
        print("Stopped by user.")

    finally:
        staff.clear()
        staff.show()


if __name__ == "__main__":
    main()
