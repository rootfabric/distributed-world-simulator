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
