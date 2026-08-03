#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_EXECUTABLE="${1:-${GODOT_BIN:-}}"
if [[ -z "$GODOT_EXECUTABLE" || ! -x "$GODOT_EXECUTABLE" ]]; then
  echo "Godot 4.7.1 double executable is required as argument or GODOT_BIN." >&2
  exit 2
fi
"$GODOT_EXECUTABLE" --path "$ROOT_DIR" --rendering-method gl_compatibility res://scenes/labs/character/character_presentation_lab.tscn
