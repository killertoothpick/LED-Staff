from __future__ import annotations

# Allow running this file directly, e.g. `sudo .venv/bin/python tools/test_*.py`.
# Python normally puts tools/ on sys.path, not the project root.
import sys
from pathlib import Path
PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

import time

from hardware.buttons import ButtonScanner


def main():
    buttons = ButtonScanner()
    print("Press buttons. Ctrl+C to exit.")
    try:
        while True:
            now = time.monotonic()
            events = buttons.update(now)
            for name, event in events.items():
                if event.pressed:
                    print(f"{name}: pressed")
                if event.tap:
                    print(f"{name}: tap")
                if event.hold:
                    print(f"{name}: HOLD")
                if event.released:
                    print(f"{name}: released")
            time.sleep(0.01)
    finally:
        buttons.cleanup()

if __name__ == "__main__":
    main()
