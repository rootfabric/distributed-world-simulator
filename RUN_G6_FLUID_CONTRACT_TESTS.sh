#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_EXECUTABLE="${GODOT_BIN:-}"
if [[ -z "$GODOT_EXECUTABLE" ]]; then
  for candidate in \
    "$ROOT_DIR/tools/godot/godot.linuxbsd.editor.double.x86_64" \
    "$ROOT_DIR/godot.linuxbsd.editor.double.x86_64" \
    "godot4" \
    "godot"; do
    if command -v "$candidate" >/dev/null 2>&1; then
      GODOT_EXECUTABLE="$(command -v "$candidate")"
      break
    elif [[ -x "$candidate" ]]; then
      GODOT_EXECUTABLE="$candidate"
      break
    fi
  done
fi
if [[ -z "$GODOT_EXECUTABLE" ]]; then
  echo "Godot executable not found. Set GODOT_BIN to a Godot 4.7.1 double-precision binary." >&2
  exit 1
fi
export BREAKPOINT_RUNTIME_DISABLED=1
"$GODOT_EXECUTABLE" --headless --editor --path "$ROOT_DIR" --quit
"$GODOT_EXECUTABLE" --headless --path "$ROOT_DIR" --script res://tests/procedural/features/g5_world_feature_graph_acceptance.gd
"$GODOT_EXECUTABLE" --headless --path "$ROOT_DIR" --script res://tests/procedural/features/g5_feature_cell_identity_acceptance.gd
"$GODOT_EXECUTABLE" --headless --path "$ROOT_DIR" --script res://tests/procedural/hydrology/g6_fluid_contracts_acceptance.gd
echo "G6.0 fluid contracts focused gate passed."
