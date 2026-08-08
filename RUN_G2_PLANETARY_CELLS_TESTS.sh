#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_EXECUTABLE="${GODOT_BIN:-}"
if [[ -z "$GODOT_EXECUTABLE" ]]; then
  for candidate in \
    "$ROOT_DIR/tools/godot/godot.linuxbsd.editor.double.x86_64" \
    "$ROOT_DIR/godot.linuxbsd.editor.double.x86_64" \
    "$(command -v godot 2>/dev/null || true)" \
    "$(command -v godot4 2>/dev/null || true)"; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      GODOT_EXECUTABLE="$candidate"
      break
    fi
  done
fi
if [[ -z "$GODOT_EXECUTABLE" || ! -x "$GODOT_EXECUTABLE" ]]; then
  echo "Godot executable not found. Set GODOT_BIN to the Godot 4.7.1 double-precision editor binary." >&2
  exit 2
fi

HAD_BREAKPOINT_RUNTIME_DISABLED=0
PREVIOUS_BREAKPOINT_RUNTIME_DISABLED="${BREAKPOINT_RUNTIME_DISABLED-}"
if [[ -v BREAKPOINT_RUNTIME_DISABLED ]]; then HAD_BREAKPOINT_RUNTIME_DISABLED=1; fi
restore_env() {
  if [[ "$HAD_BREAKPOINT_RUNTIME_DISABLED" -eq 1 ]]; then
    export BREAKPOINT_RUNTIME_DISABLED="$PREVIOUS_BREAKPOINT_RUNTIME_DISABLED"
  else
    unset BREAKPOINT_RUNTIME_DISABLED || true
  fi
}
trap restore_env EXIT
export BREAKPOINT_RUNTIME_DISABLED=1

"$GODOT_EXECUTABLE" --headless --editor --path "$ROOT_DIR" --quit
"$GODOT_EXECUTABLE" --headless --path "$ROOT_DIR" --script res://tests/procedural/surface/g2_planetary_cells_lod_acceptance.gd
"$GODOT_EXECUTABLE" --headless --path "$ROOT_DIR" --script res://tests/procedural/surface/g2_fly_in_lod_continuity.gd
