#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_EXECUTABLE="${GODOT_BIN:-}"

if [[ -z "$GODOT_EXECUTABLE" ]]; then
  for candidate in \
    "$ROOT_DIR/tools/godot/linux-x86_64/godot.linuxbsd.editor.double.x86_64" \
    "$ROOT_DIR/godot.linuxbsd.editor.double.x86_64"; do
    if [[ -x "$candidate" ]]; then
      GODOT_EXECUTABLE="$candidate"
      break
    fi
  done
fi

if [[ -z "$GODOT_EXECUTABLE" || ! -x "$GODOT_EXECUTABLE" ]]; then
  echo "Godot executable not found. Set GODOT_BIN to the Godot 4.7.1 double-precision editor binary." >&2
  exit 1
fi

export BREAKPOINT_RUNTIME_DISABLED=1

echo "=== G7.3 editor import / parse ==="
"$GODOT_EXECUTABLE" --headless --editor --path "$ROOT_DIR" --quit

for test_script in \
  res://tests/procedural/semantic_fields/g7_0_semantic_field_contracts_acceptance.gd \
  res://tests/procedural/semantic_fields/g7_1_upstream_semantic_field_adapters_acceptance.gd \
  res://tests/procedural/semantic_fields/g7_2_composition_provenance_acceptance.gd \
  res://tests/procedural/semantic_fields/g7_3_cross_cell_cross_lod_invariance_acceptance.gd; do
  echo "Running $test_script"
  "$GODOT_EXECUTABLE" --headless --path "$ROOT_DIR" --script "$test_script"
done

echo "G7.3 Cross-Cell / Cross-LOD Invariance focused gate passed."
