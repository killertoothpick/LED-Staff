from __future__ import annotations

# Run with: sudo .venv/bin/python tools/test_main_only.py
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

    pin = getattr(board, config.MAIN_PIXEL_PIN)
    print(f"Testing MAIN only on board.{config.MAIN_PIXEL_PIN} with {config.MAIN_COUNT} LEDs")
    pixels = neopixel.NeoPixel(
        pin,
        config.MAIN_COUNT,
        brightness=0.15,
        auto_write=False,
        pixel_order=neopixel.GRB,
    )
    try:
        pixels.fill((0, 0, 0)); pixels.show(); time.sleep(0.25)
        print("Control circle blue")
        for i in range(16): pixels[i] = (0,0,80)
        pixels.show(); time.sleep(1)
        print("Shaft red")
        pixels.fill((0,0,0))
        for i in range(16, config.MAIN_COUNT): pixels[i] = (80,0,0)
        pixels.show(); time.sleep(1)
    finally:
        pixels.fill((0,0,0)); pixels.show()


if __name__ == "__main__":
    main()
