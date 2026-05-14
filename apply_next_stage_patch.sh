#!/usr/bin/env bash
set -euo pipefail

cd "${1:-$PWD}"

python - <<'PY'
from pathlib import Path

root = Path.cwd()
required = ["config.py", "main.py", "hardware/leds.py", "hardware/buttons.py"]
missing = [p for p in required if not (root / p).exists()]
if missing:
    raise SystemExit(f"This does not look like the led_staff project root. Missing: {missing}")

# 1) Confirmed physical button mapping.
p = root / "config.py"
text = p.read_text()
start = text.index("BUTTON_PINS = {")
end = text.index("}\n", start) + 2
prefix_start = text.rfind("# Button pins", 0, start)
if prefix_start == -1:
    prefix_start = start
replacement = '''# Button pins are BCM numbers, mapped to the CONFIRMED physical button layout.
# Physical layout:
#   [ TL ] [ TR ]
#   [ BL ] [ BC ] [ BR ]
# Confirmed hardware test mapping:
#   physical TL -> GPIO24
#   physical TR -> GPIO27
#   physical BL -> GPIO23
#   physical BC -> GPIO22
#   physical BR -> GPIO17
BUTTON_PINS = {
    "TL": 24,
    "TR": 27,
    "BL": 23,
    "BC": 22,
    "BR": 17,
}
'''
# Replace from the comment if it is adjacent; otherwise just replace the dict.
line_after = text.find("\n\n", end)
if prefix_start < start and line_after != -1:
    text = text[:prefix_start] + replacement + text[line_after:]
else:
    text = text[:start] + replacement + text[end:]
p.write_text(text)

# 2) Make audio requirements match the working hardware test path; aubio is later.
(root / "requirements-audio.txt").write_text('''# Optional audio-input dependencies.
# aubio is intentionally not installed here because Python 3.13/NumPy builds can fail.
# The current runtime uses hardware/audio.py for mic volume and hardware/beat.py for a placeholder beat clock.
numpy
sounddevice
''')

# 3) Fix TiltSpiral speed multiplier so it does not grow exponentially in Fast/Very Fast.
p = root / "animations" / "spiral.py"
text = p.read_text()
old = '''        speed = ctx.settings.speed
        if speed.mode == "beat":
            if ctx.beat.just_beat:
                self.pace += 8.0
        else:
            self.pace *= float(speed.multiplier or 1.0)

        self.count += self.pace * ctx.dt * 12.0
'''
new = '''        speed = ctx.settings.speed
        pace_for_frame = self.pace
        if speed.mode == "beat":
            if ctx.beat.just_beat:
                pace_for_frame += 8.0
        else:
            # Apply the speed setting to this frame's movement only.
            # Do not multiply self.pace itself every frame, or Fast/Very Fast grows exponentially.
            pace_for_frame *= float(speed.multiplier or 1.0)

        self.count += pace_for_frame * ctx.dt * 12.0
'''
if old in text:
    p.write_text(text.replace(old, new))

# 4) Remember selected preset slot when loading, so next boot uses it.
p = root / "core" / "presets.py"
text = p.read_text()
old = '''    def get(self, slot: int) -> Settings:
        return self.presets[slot % PRESET_SLOTS].copy()

    def set(self, slot: int, settings: Settings) -> None:
        slot %= PRESET_SLOTS
        self.presets[slot] = settings.copy()
        self.last_active_slot = slot
        self.save_file()
'''
new = '''    def get(self, slot: int) -> Settings:
        return self.presets[slot % PRESET_SLOTS].copy()

    def remember_active_slot(self, slot: int) -> None:
        """Persist which preset slot should be used at next boot."""
        slot %= PRESET_SLOTS
        if self.last_active_slot != slot:
            self.last_active_slot = slot
            self.save_file()

    def set(self, slot: int, settings: Settings) -> None:
        slot %= PRESET_SLOTS
        self.presets[slot] = settings.copy()
        self.last_active_slot = slot
        self.save_file()
'''
if old in text:
    p.write_text(text.replace(old, new))

p = root / "ui" / "pages.py"
text = p.read_text()
old = '''    def on_apply(self, settings: Settings, ui: UIState, presets: PresetStore | None, now: float) -> Settings | None:
        if presets is not None:
            loaded = presets.get(ui.preset_slot)
            ui.flash_message("loaded", now)
            return loaded
        return None
'''
new = '''    def on_apply(self, settings: Settings, ui: UIState, presets: PresetStore | None, now: float) -> Settings | None:
        if presets is not None:
            loaded = presets.get(ui.preset_slot)
            presets.remember_active_slot(ui.preset_slot)
            ui.flash_message("loaded", now)
            return loaded
        return None
'''
if old in text:
    p.write_text(text.replace(old, new))

# 5) Generate a correct systemd installer for this checkout path and venv.
p = root / "scripts" / "install_service.sh"
p.write_text('''#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON_BIN="$PROJECT_DIR/.venv/bin/python"
SERVICE_PATH="/etc/systemd/system/led-staff.service"

if [ ! -x "$PYTHON_BIN" ]; then
  echo "Expected venv Python at $PYTHON_BIN" >&2
  echo "Run ./scripts/install_python_core.sh first." >&2
  exit 1
fi

sudo tee "$SERVICE_PATH" >/dev/null <<EOF
[Unit]
Description=LED Staff Runtime
After=local-fs.target systemd-modules-load.service systemd-udev-trigger.service
Wants=local-fs.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=$PROJECT_DIR
Environment=PYTHONUNBUFFERED=1
# Audio is enabled because hardware testing confirmed the I2S mic works.
Environment=LED_STAFF_AUDIO=1
ExecStart=$PYTHON_BIN -u $PROJECT_DIR/main.py
Restart=always
RestartSec=1
TimeoutStartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable led-staff.service
sudo systemctl restart led-staff.service
sudo systemctl status led-staff.service --no-pager
''')
p.chmod(0o755)

print("Next-stage patch applied.")
PY

python -m compileall -q .
echo "Compile check passed."
