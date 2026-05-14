from __future__ import annotations

import json
import os
import random
from dataclasses import dataclass
from pathlib import Path

import config
from core.palettes import PALETTES
from core.settings import Settings


@dataclass
class PresetStore:
    path: Path
    presets: list[Settings]
    last_active_slot: int = 0

    @classmethod
    def load(cls, path: str | Path, animation_count: int | None = None) -> "PresetStore":
        path = Path(path)
        presets = [Settings() for _ in range(config.PRESET_SLOTS)]
        last_active_slot = 0
        try:
            if path.exists():
                data = json.loads(path.read_text())
                last_active_slot = int(data.get("last_active_slot", 0)) % config.PRESET_SLOTS
                loaded = data.get("presets", [])
                for i, item in enumerate(loaded[:config.PRESET_SLOTS]):
                    settings_data = item.get("settings", item) if isinstance(item, dict) else {}
                    presets[i] = Settings.from_json(settings_data)
                    presets[i].clamp(animation_count)
        except Exception as exc:
            print(f"Preset load failed, using defaults: {exc}")

        store = cls(path=path, presets=presets, last_active_slot=last_active_slot)
        store.randomize_boot_visual_slots(animation_count)
        return store

    def randomize_boot_visual_slots(self, animation_count: int | None) -> None:
        """Give the last preset slots fresh visuals at boot.

        Only animation_index and palette_index are randomized. Mechanism settings
        such as speed, brightness, and gain stay exactly as saved in the file.
        The randomization is intentionally not written immediately; it is the
        starting visual for this boot. It will be saved only if the user changes
        away from that slot or otherwise persists the current slot.
        """
        count = max(0, int(getattr(config, "RANDOM_VISUAL_PRESET_COUNT", 0)))
        if count <= 0:
            return
        start = max(0, config.PRESET_SLOTS - count)
        safe_animation_count = max(1, int(animation_count or 1))
        for slot in range(start, config.PRESET_SLOTS):
            preset = self.presets[slot]
            preset.animation_index = random.randrange(safe_animation_count)
            preset.palette_index = random.randrange(len(PALETTES))
            preset.clamp(animation_count)

    def save_file(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        data = {
            "version": 2,
            "last_active_slot": self.last_active_slot % config.PRESET_SLOTS,
            "random_visual_preset_count": getattr(config, "RANDOM_VISUAL_PRESET_COUNT", 0),
            "presets": [
                {"name": f"Preset {i + 1}", "settings": preset.to_json()}
                for i, preset in enumerate(self.presets[:config.PRESET_SLOTS])
            ],
        }
        tmp = self.path.with_suffix(self.path.suffix + ".tmp")
        tmp.write_text(json.dumps(data, indent=2))
        os.replace(tmp, self.path)

    def get(self, slot: int) -> Settings:
        return self.presets[slot % config.PRESET_SLOTS].copy()

    def save_current(self, slot: int, settings: Settings, *, remember: bool = True) -> None:
        """Save the current runtime settings into a slot and write presets.json."""
        slot %= config.PRESET_SLOTS
        self.presets[slot] = settings.copy()
        if remember:
            self.last_active_slot = slot
        self.save_file()

    def remember_active_slot(self, slot: int) -> None:
        slot %= config.PRESET_SLOTS
        self.last_active_slot = slot
        self.save_file()

    def set(self, slot: int, settings: Settings) -> None:
        self.save_current(slot, settings, remember=True)
