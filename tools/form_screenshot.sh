#!/usr/bin/env bash
# Renders the form kit to docs/form_*.png: desktop dark, light, search, collapsed, list reorder and the on-screen keyboard, and a phone viewport.
set -euo pipefail
cd "$(dirname "$0")/.."
xvfb-run -a godot --path . --resolution 1280x800 res://examples/form_demo.tscn -- --shots=dark,light,search,collapsed,reorder,keypad,light_keypad,modified
xvfb-run -a godot --path . --resolution 390x844 res://examples/form_demo.tscn -- --shots=phone_dark,phone_light,phone_reorder,phone_keypad
