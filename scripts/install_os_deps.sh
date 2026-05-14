#!/usr/bin/env bash
set -euo pipefail

# Raspberry Pi OS packages needed to build/use the Pi hardware Python packages.
# This fixes common pip errors like: fatal error: Python.h: No such file or directory

PY_BIN="${PY_BIN:-python3}"
PY_MM="$($PY_BIN - <<'PY'
import sys
print(f"{sys.version_info.major}.{sys.version_info.minor}")
PY
)"

sudo apt update

# Try the exact Python dev package first. This matters if the venv uses Python 3.13.
if apt-cache show "python${PY_MM}-dev" >/dev/null 2>&1; then
  PY_DEV="python${PY_MM}-dev"
else
  PY_DEV="python3-dev"
fi

sudo apt install -y \
  "$PY_DEV" \
  python3-venv \
  build-essential \
  pkg-config \
  libffi-dev \
  i2c-tools \
  python3-smbus \
  libasound2-dev \
  portaudio19-dev \
  libsndfile1-dev \
  libsamplerate0-dev \
  libaubio-dev

echo "Installed OS build/runtime dependencies using $PY_DEV"
