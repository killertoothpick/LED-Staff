#!/usr/bin/env bash
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
Environment=MALLOC_ARENA_MAX=2
Environment=LED_STAFF_DEBUG=0
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
