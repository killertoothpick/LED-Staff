# Troubleshooting Install Errors

## `Python.h: No such file or directory`

This means pip is compiling a native Python extension but the development headers for the Python inside `.venv` are not installed.

Your failing log showed builds for `RPi.GPIO`, `aubio`, and `rpi_ws281x` all looking in `/usr/include/python3.13` and then failing to find `Python.h`. That means the venv is using Python 3.13 and needs the matching headers.

Try:

```bash
cd ~/led_staff
./scripts/install_os_deps.sh
. .venv/bin/activate
python -m pip install --upgrade pip setuptools wheel
python -m pip install -r requirements.txt
```

If the venv is Python 3.13 and the script cannot find the exact dev package:

```bash
sudo apt update
sudo apt install -y python3.13-dev build-essential pkg-config
```

If `python3.13-dev` is not available from your OS repositories, recreate the venv with the OS-supported Python, usually the default `python3`:

```bash
rm -rf .venv
python3 -m venv .venv
./scripts/install_python_core.sh
```

## Core first, audio later

`aubio` is optional for now. The current runtime uses a placeholder beat tracker, so the staff can run without aubio. Install audio later with:

```bash
./scripts/install_python_audio.sh
```

## Do not make boot wait for Wi-Fi

The systemd service does not depend on `network-online.target`. If boot still stalls on network, check for wait-online services:

```bash
systemctl is-enabled NetworkManager-wait-online.service || true
systemctl is-enabled systemd-networkd-wait-online.service || true
```

Disable any wait-online service you do not need:

```bash
sudo systemctl disable NetworkManager-wait-online.service 2>/dev/null || true
sudo systemctl disable systemd-networkd-wait-online.service 2>/dev/null || true
```


## ModuleNotFoundError: No module named 'core'

This happens when Python is launched on a file inside `tools/` and only that folder is placed on the import path. Version 1.2 patches the test tools to add the project root automatically. Also make sure you use the virtualenv interpreter, not the system Python:

```bash
cd ~/led_staff_v1
sudo .venv/bin/python tools/test_led_sections.py
```

Do not use plain `sudo python ...` unless you intentionally installed all dependencies into the system Python.

## Top LEDs do not light

First confirm the pin naming: `board.D12` means **GPIO12**, which is physical header pin **32**. It does **not** mean physical pin 12. Physical pin 12 is GPIO18, written as `board.D18`.

Your uploaded pinout says the top/WS2812B Data 1 line is physical pin 32, so the default should usually stay:

```python
TOP_PIXEL_PIN = "D12"
```

Run the top-only test:

```bash
cd ~/led_staff_v1
sudo .venv/bin/python tools/test_top_only.py
```

If the top-only test fails but the main strip works:

1. Verify the top data wire is on physical pin 32 / GPIO12.
2. Verify top LED 5V and GND are present.
3. Verify top LED ground is common with the Pi ground.
4. Verify the top strip data input is connected to the DIN side, not DOUT.
5. If you moved the top to physical pin 12, set `TOP_PIXEL_PIN = "D18"`, but note that your pinout also uses physical pin 12 for Mic Clock, so that conflicts with the planned I2S mic.
6. Try a level shifter if the strip is powered at 5V and does not reliably accept the Pi's 3.3V data signal.

The main and top pin settings now live in `config.py`:

```python
MAIN_PIXEL_PIN = "D13"
TOP_PIXEL_PIN = "D12"
```
