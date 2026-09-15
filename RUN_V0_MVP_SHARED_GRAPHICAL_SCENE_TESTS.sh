#!/usr/bin/env bash
set -euo pipefail

: "${GODOT_BIN:?Set GODOT_BIN to the pinned Godot 4.7.1 double executable}"

"$GODOT_BIN" --headless --path . -s res://tests/runtime/test_v0_mvp_shared_graphical_scene.gd
