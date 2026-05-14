#!/usr/bin/env bash
set -euo pipefail

if [ ! -d .venv ]; then
  echo ".venv not found. Run scripts/install_python_core.sh first."
  exit 1
fi

. .venv/bin/activate
python -m pip install --upgrade pip setuptools wheel
python -m pip install -r requirements-audio.txt

echo "Optional audio Python dependencies installed."
