#!/usr/bin/env bash
# Renders the shared screens to screenshots/ so a person can look at them.
#
#   tools/screenshot.sh
#
# Uses xvfb-run because this needs a rendering context and the machines this runs on have
# no display. Nothing here is headless-safe: `--headless` gives a null renderer and every
# frame it saves is empty, which is worse than no screenshot because it looks like one.
#
# This is the addon that DRAWS, and until now it was the one place in the family with no
# picture of anything. Every check in its suite is a size, a focus path or a visibility
# flag, and this tree has shipped a 0 x 0 Control twice.
set -euo pipefail
cd "$(dirname "$0")/.."
exec xvfb-run -a godot --path . --resolution 1280x800 --script tools/screenshot.gd
