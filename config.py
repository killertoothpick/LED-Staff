"""Central configuration for the LED staff runtime.

Edit this file first when the hardware mapping changes.
"""
from __future__ import annotations

import os

# Set LED_STAFF_MOCK=1 to run on a non-Raspberry Pi machine for dry tests.
MOCK_HARDWARE = os.environ.get("LED_STAFF_MOCK", "0") == "1"

TARGET_FPS = 60
FRAME_TIME = 1.0 / TARGET_FPS
FPS_LOG_INTERVAL = 5.0

# LED layout
MAIN_COUNT = 215
TOP_COUNT = 7
# Top geometry, revised after hardware bring-up. The top is two mirrored
# physical strands of 7 LEDs. Software sends 7 logical pixels; each logical
# index lights the same-numbered LED on both strands.
TOP_LOGICAL_COUNT = 7
TOP_TRIANGLE_SHARED_COUNT = 2
TOP_TRIANGLE_BRANCH_COUNT = 5
# LED data pins use BCM GPIO numbers in board.Dxx form, NOT physical header pin numbers.
# Your uploaded pinout: physical pin 33 = GPIO13 = board.D13 for main strip.
# Your uploaded pinout: physical pin 32 = GPIO12 = board.D12 for top strip.
# If the top strip is still wired to physical pin 32, leave TOP_PIXEL_PIN = "D12".
MAIN_PIXEL_PIN = "D13"
TOP_PIXEL_PIN = "D12"

CONTROL_START = 0
CONTROL_END = 15
CONTROL_COUNT = CONTROL_END - CONTROL_START + 1

# Logical direction for the 16-LED control circle while using it as a dial.
# Increase moves clockwise; decrease moves counter-clockwise. If the physical
# ring ever appears reversed, flip CONTROL_DIAL_CLOCKWISE between 1 and -1.
CONTROL_DIAL_ZERO = 0
CONTROL_DIAL_CLOCKWISE = -1

SHAFT_RIGHT_START = 16
SHAFT_RIGHT_END = 114  # inclusive, right side runs downward
SHAFT_LEFT_START = 115
SHAFT_LEFT_END = 214   # inclusive, left side is wired upward
SHAFT_DEPTH = 100

# Brightness safety. The actual selected brightness is applied in software too.
DEFAULT_MAIN_BRIGHTNESS = 1.0
DEFAULT_TOP_BRIGHTNESS = 1.0
MAX_OUTPUT_SCALE = 1.0

# Button pins are BCM numbers, mapped to the CONFIRMED physical button layout.
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
    # Logical names mapped to confirmed physical buttons.
    # Physical layout:
    # [ TL ] [ TR ]
    # [ BL ] [ BC ] [ BR ]
    "TL": 24,
    "TR": 27,
    "BL": 23,
    "BC": 22,
    "BR": 17,
}

BUTTON_DEBOUNCE_SEC = 0.030
BUTTON_HOLD_SEC = 1.0
SETTINGS_TIMEOUT_SEC = 15.0



# Presets
PRESET_PATH = "data/presets.json"
PRESET_SLOTS = 9


# The last N preset slots keep saved mechanism settings, but get a fresh
# random visual pairing (animation + palette) at each boot.
RANDOM_VISUAL_PRESET_COUNT = 5
# Audio / beat placeholders. Audio can be enabled once the mic is configured.
ENABLE_AUDIO = os.environ.get("LED_STAFF_AUDIO", "0") == "1"
AUDIO_SAMPLE_RATE = 44100
AUDIO_BLOCK_SIZE = 1024
DEFAULT_BPM = 120.0

# Live terminal dashboard. Enabled by default when run manually in a terminal.
# Use LED_STAFF_DEBUG=0 to go back to plain logs.
DEBUG_CONSOLE = os.environ.get("LED_STAFF_DEBUG", "1") != "0"
DEBUG_CONSOLE_HZ = float(os.environ.get("LED_STAFF_DEBUG_HZ", "4"))
DEBUG_LOG_LINES = int(os.environ.get("LED_STAFF_DEBUG_LOG_LINES", "8"))

# IMU axis convention confirmed on hardware. Values are passed through raw,
# but this documents how to interpret them in animations/debug output.
IMU_AXIS_X = "right"
IMU_AXIS_Y = "up"
IMU_AXIS_Z = "perpendicular"


# Runtime memory stability. The Pi can keep freed C-extension memory in RSS
# unless glibc is asked to trim periodically. This keeps the long-running
# systemd service from slowly drifting into OOM territory.
MEMORY_MAINTENANCE_SEC = float(os.environ.get("LED_STAFF_MEMORY_MAINTENANCE_SEC", "15"))
MEMORY_LOG_SEC = float(os.environ.get("LED_STAFF_MEMORY_LOG_SEC", "60"))
MEMORY_TRIM_ENABLED = os.environ.get("LED_STAFF_MEMORY_TRIM", "1") != "0"
