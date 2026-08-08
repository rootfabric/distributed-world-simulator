#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$ROOT_DIR/RUN_G6_1_CASUAL_RIVER_PROVIDER_TESTS.sh"
GODOT_EXECUTABLE="${GODOT_BIN:-}"
if [[ -z "$GODOT_EXECUTABLE" ]]; then
  for candidate in "$ROOT_DIR/tools/godot/godot.linuxbsd.editor.double.x86_64" "$ROOT_DIR/godot.linuxbsd.editor.double.x86_64" "$(command -v godot 2>/dev/null || true)" "$(command -v godot4 2>/dev/null || true)"; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then GODOT_EXECUTABLE="$candidate"; break; fi
  done
fi
if [[ -z "$GODOT_EXECUTABLE" || ! -x "$GODOT_EXECUTABLE" ]]; then echo "Godot executable not found. Set GODOT_BIN." >&2; exit 2; fi
PREVIOUS_BREAKPOINT_RUNTIME_DISABLED="${BREAKPOINT_RUNTIME_DISABLED-__UNSET__}"
export BREAKPOINT_RUNTIME_DISABLED=1
cleanup() {
  if [[ "$PREVIOUS_BREAKPOINT_RUNTIME_DISABLED" == "__UNSET__" ]]; then unset BREAKPOINT_RUNTIME_DISABLED; else export BREAKPOINT_RUNTIME_DISABLED="$PREVIOUS_BREAKPOINT_RUNTIME_DISABLED"; fi
}
trap cleanup EXIT
"$GODOT_EXECUTABLE" --headless --path "$ROOT_DIR" --script res://tests/procedural/hydrology/g6_2_cross_cell_cross_lod_continuity_acceptance.gd
echo "G6.2 cross-cell/cross-LOD continuity focused gate passed."
