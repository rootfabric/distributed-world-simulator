#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_EXECUTABLE="${GODOT_BIN:-}"
if [[ -z "$GODOT_EXECUTABLE" ]]; then
  for candidate in "$ROOT_DIR/tools/godot/godot.linuxbsd.editor.double.x86_64" "$ROOT_DIR/godot.linuxbsd.editor.double.x86_64" "$(command -v godot 2>/dev/null || true)" "$(command -v godot4 2>/dev/null || true)"; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then GODOT_EXECUTABLE="$candidate"; break; fi
  done
fi
if [[ -z "$GODOT_EXECUTABLE" || ! -x "$GODOT_EXECUTABLE" ]]; then echo "Godot executable not found. Set GODOT_BIN to the Godot 4.7.1 double-precision editor binary." >&2; exit 2; fi
PREVIOUS_BREAKPOINT_RUNTIME_DISABLED="${BREAKPOINT_RUNTIME_DISABLED-__UNSET__}"
export BREAKPOINT_RUNTIME_DISABLED=1
cleanup() {
  if [[ "$PREVIOUS_BREAKPOINT_RUNTIME_DISABLED" == "__UNSET__" ]]; then unset BREAKPOINT_RUNTIME_DISABLED; else export BREAKPOINT_RUNTIME_DISABLED="$PREVIOUS_BREAKPOINT_RUNTIME_DISABLED"; fi
}
trap cleanup EXIT
"$GODOT_EXECUTABLE" --headless --editor --path "$ROOT_DIR" --quit
"$GODOT_EXECUTABLE" --headless --path "$ROOT_DIR" --script res://tests/procedural/hydrology/g6_hydrology_fluid_surface_acceptance.gd
"$GODOT_EXECUTABLE" --headless --path "$ROOT_DIR" --script res://tests/procedural/hydrology/g6_river_cell_lod_identity_acceptance.gd
"$GODOT_EXECUTABLE" --headless --path "$ROOT_DIR" --scene res://scenes/labs/procedural/g6_hydrology_fluid_surface_lab.tscn --quit-after 2
