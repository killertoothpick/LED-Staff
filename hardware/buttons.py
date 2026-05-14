from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict

import config


@dataclass
class ButtonEvent:
    pressed: bool = False
    released: bool = False
    tap: bool = False
    hold: bool = False
    held: bool = False


@dataclass
class _ButtonState:
    stable_down: bool = False
    raw_down: bool = False
    last_raw_change: float = 0.0
    pressed_at: float = 0.0
    hold_fired: bool = False


class ButtonScanner:
    def __init__(self, pins: dict[str, int] | None = None):
        self.pins = dict(pins or config.BUTTON_PINS)
        self.states: dict[str, _ButtonState] = {name: _ButtonState() for name in self.pins}
        self._mock_raw: dict[str, bool] = {name: False for name in self.pins}

        if not config.MOCK_HARDWARE:
            import RPi.GPIO as GPIO

            self.GPIO = GPIO
            GPIO.setmode(GPIO.BCM)
            for pin in self.pins.values():
                GPIO.setup(pin, GPIO.IN, pull_up_down=GPIO.PUD_UP)
        else:
            self.GPIO = None

    def cleanup(self) -> None:
        if self.GPIO is not None:
            self.GPIO.cleanup()

    def set_mock_down(self, name: str, down: bool) -> None:
        self._mock_raw[name] = down

    def _read_raw_down(self, name: str) -> bool:
        if config.MOCK_HARDWARE:
            return self._mock_raw.get(name, False)
        assert self.GPIO is not None
        return self.GPIO.input(self.pins[name]) == self.GPIO.LOW

    def update(self, now: float) -> dict[str, ButtonEvent]:
        events: dict[str, ButtonEvent] = {}
        for name, state in self.states.items():
            event = ButtonEvent()
            raw_down = self._read_raw_down(name)

            if raw_down != state.raw_down:
                state.raw_down = raw_down
                state.last_raw_change = now

            # Commit raw state to stable state after debounce interval.
            if (now - state.last_raw_change) >= config.BUTTON_DEBOUNCE_SEC and raw_down != state.stable_down:
                state.stable_down = raw_down
                if state.stable_down:
                    event.pressed = True
                    state.pressed_at = now
                    state.hold_fired = False
                else:
                    event.released = True
                    held_for = now - state.pressed_at
                    if held_for < config.BUTTON_HOLD_SEC and not state.hold_fired:
                        event.tap = True
                    state.hold_fired = False

            if state.stable_down:
                event.held = True
                if not state.hold_fired and (now - state.pressed_at) >= config.BUTTON_HOLD_SEC:
                    event.hold = True
                    state.hold_fired = True

            events[name] = event
        return events
