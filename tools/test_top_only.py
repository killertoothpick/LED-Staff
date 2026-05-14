from __future__ import annotations

# Run with: sudo .venv/bin/python tools/test_top_only.py
import sys
from pathlib import Path
PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

import time
import config


def main():
    import board
    import neopixel

    pin = getattr(board, config.TOP_PIXEL_PIN)
    print(f"Testing TOP only on board.{config.TOP_PIXEL_PIN} with {config.TOP_COUNT} logical LEDs")
    print("The two physical 7-LED top strands should mirror each logical LED.")
    print("Example: logical top LED 3 should light LED 3 on both left and right strands.")
    print("Reminder: board.D12 = GPIO12 = physical pin 32. board.D18 = GPIO18 = physical pin 12.")

    pixels = neopixel.NeoPixel(
        pin,
        config.TOP_COUNT,
        brightness=0.25,
        auto_write=False,
<<<<<<< HEAD
        pixel_order=neopixel.RGB,
=======
        pixel_order=neopixel.GRB,
>>>>>>> all-systems-go-current
    )
    try:
        pixels.fill((0, 0, 0)); pixels.show(); time.sleep(0.25)
        for color_name, color in [("red", (80, 0, 0)), ("green", (0, 80, 0)), ("blue", (0, 0, 80)), ("white", (40, 40, 40))]:
            print(f"Both top strands should be {color_name}")
            pixels.fill(color); pixels.show(); time.sleep(0.8)

        print("Shared triangle side: first 2 mirrored LEDs")
        pixels.fill((0, 0, 0))
        for i in range(min(config.TOP_TRIANGLE_SHARED_COUNT, config.TOP_COUNT)):
            pixels[i] = (80, 80, 0)
        pixels.show(); time.sleep(1.2)

        print("Branch sides: remaining 5 mirrored LEDs")
        pixels.fill((0, 0, 0))
        for i in range(config.TOP_TRIANGLE_SHARED_COUNT, config.TOP_COUNT):
            pixels[i] = (0, 80, 80)
        pixels.show(); time.sleep(1.2)

        print("Mirrored logical chase kept intentionally: each step should appear on both strands")
        for _ in range(4):
            for i in range(config.TOP_COUNT):
                pixels.fill((0, 0, 0))
                pixels[i] = (80, 80, 80)
                pixels.show()
                time.sleep(0.12)
    finally:
        pixels.fill((0, 0, 0)); pixels.show()


if __name__ == "__main__":
    main()
