#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_EXECUTABLE="${1:-${GODOT_BIN:-}}"
if [[ -z "$GODOT_EXECUTABLE" || ! -x "$GODOT_EXECUTABLE" ]]; then
  echo "Godot 4.7.1 double executable is required as argument or GODOT_BIN." >&2
  exit 2
fi
export GODOT_SILENCE_ROOT_WARNING=1
"$GODOT_EXECUTABLE" --headless --editor --path "$ROOT_DIR" --quit
"$GODOT_EXECUTABLE" --headless --path "$ROOT_DIR" --script res://tests/characters/test_ch1_character_contracts_and_registry.gd
"$GODOT_EXECUTABLE" --headless --path "$ROOT_DIR" --script res://tests/characters/test_ch2_humanoid_import_lab.gd
"$GODOT_EXECUTABLE" --headless --path "$ROOT_DIR" --script res://tests/characters/test_ch3_isolated_presentation_host.gd
if command -v xvfb-run >/dev/null 2>&1; then
  timeout 90s xvfb-run -a -s '-screen 0 1280x720x24' "$GODOT_EXECUTABLE" --audio-driver Dummy --path "$ROOT_DIR" --rendering-method gl_compatibility --script res://tests/characters/test_ch3_character_lab_graphical.gd
elif [[ -n "${DISPLAY:-}" ]]; then
  "$GODOT_EXECUTABLE" --audio-driver Dummy --path "$ROOT_DIR" --rendering-method gl_compatibility --script res://tests/characters/test_ch3_character_lab_graphical.gd
else
  echo "Graphical smoke skipped: neither xvfb-run nor DISPLAY is available." >&2
  exit 3
fi
