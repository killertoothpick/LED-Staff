#!/usr/bin/env bash
set -euo pipefail

PY_BIN="${PY_BIN:-python3}"

if [ ! -d .venv ]; then
  "$PY_BIN" -m venv .venv
fi

. .venv/bin/activate
python -m pip install --upgrade pip setuptools wheel
python -m pip install -r requirements.txt

echo "Core Python dependencies installed."
