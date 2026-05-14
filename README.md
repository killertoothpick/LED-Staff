# LED Staff Runtime v1

This is the first runnable refactor of the LED staff software. It preserves the current hardware assumptions and introduces the architecture needed for the settings UI, presets, audio, beat data, and IMU-aware animations.

## What is included now

- Logical LED sections:
  - top strip: 36 LEDs on `board.D12`
  - control circle: main strip LEDs 0-15
  - shaft: main strip LEDs 16-214
- Shaft mapping for right-side-down and left-side-up wiring.
- Five-button non-blocking scanner.
- Main 60 FPS frame loop.
- Active/pending settings model.
- Settings mode:
  - BC tap enters settings
  - BL/BR cycles pages
  - TL/TR adjusts values
  - BC tap applies
  - BC hold cancels
  - 15s timeout cancels
- Settings pages:
  - Animation
  - Palette
  - Speed
  - Brightness
  - Gain
  - Save Preset
  - Load Preset
- Preset JSON support.
- IMU reader with safe fallback.
- Audio state placeholder with optional `sounddevice` input.
- Beat tracker placeholder so Beat speed can be tested before aubio is wired in.
- systemd service that does not wait for Wi-Fi.

## Hardware note

The default button mapping is in `config.py`:

```python
BUTTON_PINS = {
    "TL": 17,
    "TR": 27,
    "BL": 22,
    "BC": 24,
    "BR": 23,
}
```

GPIO24 is assigned to bottom-center because it was the mode-cycle button in the original script. Run `tools/test_buttons.py` and adjust this mapping if the physical layout differs.

## Install on the Pi

Start with the core runtime first. Audio/beat dependencies are split out so the LEDs/buttons/IMU can be brought up before the I2S mic stack is ready.

```bash
cd /home/pi
cp -r led_staff_v1 led_staff
cd /home/pi/led_staff

# Installs compiler headers and native libraries needed by Pi hardware packages.
./scripts/install_os_deps.sh

# Creates .venv if missing and installs the core runtime dependencies.
./scripts/install_python_core.sh
```

If you are using a non-default Python, set `PY_BIN` first. Example:

```bash
PY_BIN=python3.13 ./scripts/install_os_deps.sh
PY_BIN=python3.13 ./scripts/install_python_core.sh
```

The most common install failure is `fatal error: Python.h: No such file or directory`. That means the Python development headers for the exact Python version inside the venv are missing. `install_os_deps.sh` attempts to install the matching `pythonX.Y-dev` package.

After the core hardware tests pass, install optional audio/beat packages:

```bash
./scripts/install_python_audio.sh
```

## Test hardware first

```bash
sudo .venv/bin/python tools/test_led_sections.py
sudo .venv/bin/python tools/test_buttons.py
sudo .venv/bin/python tools/test_imu.py
```

Audio is off by default. After the I2S mic appears as an ALSA input and `requirements-audio.txt` has been installed:

```bash
sudo LED_STAFF_AUDIO=1 .venv/bin/python tools/test_audio_input.py
```

## Run manually

```bash
sudo .venv/bin/python main.py
```

## Install systemd service

Edit `led-staff.service` if your Python path differs, then:

```bash
sudo cp led-staff.service /etc/systemd/system/led-staff.service
sudo systemctl daemon-reload
sudo systemctl enable led-staff.service
sudo systemctl restart led-staff.service
journalctl -u led-staff.service -f
```

This service is installed under `multi-user.target` and does not depend on `network-online.target`, so it should not wait for Wi-Fi.

## Run in mock mode on a non-Pi

```bash
LED_STAFF_MOCK=1 python3 main.py
```

## Next coding milestones

1. Confirm and correct physical button mapping.
2. Tune current animation behavior on real LEDs.
3. Install optional audio dependencies, then replace the placeholder beat tracker with aubio-backed live tempo detection.
4. Add real FFT bass/mids/treble bands to `hardware/audio.py`.
5. Add audio visualizer animations using top-as-center and shaft-as-downward mapping.


## Direct tool import fix

The test scripts add the project root to `sys.path`, so they can be run directly from the project directory. Use the venv interpreter when running under sudo:

```bash
sudo .venv/bin/python tools/test_led_sections.py
sudo .venv/bin/python tools/test_buttons.py
sudo .venv/bin/python tools/test_imu.py
```

Or use the helper:

```bash
./scripts/run_test.sh tools/test_led_sections.py
```

### Top-only LED test

If the top LEDs do not light, run:

```bash
cd ~/led_staff_v1
sudo .venv/bin/python tools/test_top_only.py
```

Pin names are BCM GPIO names in `board.Dxx` form. For example, `board.D12` is GPIO12 / physical pin 32, not physical pin 12.
