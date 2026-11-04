#!/usr/bin/env bash
# Renders DotTouchButtons at phone size to screenshots/touch_buttons*.png (xvfb-run: --headless draws nothing).
set -euo pipefail
cd "$(dirname "$0")/.."
exec xvfb-run -a godot --path . --resolution 390x844 --script tools/touch_shot.gd
