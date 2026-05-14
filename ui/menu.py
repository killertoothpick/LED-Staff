from __future__ import annotations

from dataclasses import dataclass

import config
from core.settings import Settings


@dataclass
class UIState:
    in_settings: bool = False
    page_index: int = 0
    entered_page_at: float = 0.0
    last_interaction_at: float = 0.0
    preset_slot: int = 0
    message_until: float = 0.0
    message: str = ""

    def enter_settings(self, now: float, active: Settings) -> Settings:
        self.in_settings = True
        self.page_index = 0
        self.entered_page_at = now
        self.last_interaction_at = now
        self.message = ""
        self.message_until = 0.0
        return active.copy()

    def exit_settings(self) -> None:
        self.in_settings = False
        self.message = ""
        self.message_until = 0.0

    def touch(self, now: float) -> None:
        self.last_interaction_at = now

    def set_page(self, page_index: int, page_count: int, now: float) -> None:
        self.page_index = page_index % page_count
        self.entered_page_at = now
        self.touch(now)

    def timed_out(self, now: float) -> bool:
        return self.in_settings and (now - self.last_interaction_at) >= config.SETTINGS_TIMEOUT_SEC

    def flash_message(self, text: str, now: float, duration: float = 0.65) -> None:
        self.message = text
        self.message_until = now + duration
