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

"$GODOT_EXECUTABLE" --headless --editor --path "$ROOT_DIR" --quit

for test_script in \
  res://tests/procedural/semantic_fields/g7_0_semantic_field_contracts_acceptance.gd \
  res://tests/procedural/semantic_fields/g7_1_upstream_semantic_field_adapters_acceptance.gd \
  res://tests/procedural/semantic_fields/g7_2_composition_provenance_acceptance.gd \
  res://tests/procedural/semantic_fields/g7_3_cross_cell_cross_lod_invariance_acceptance.gd \
  res://tests/procedural/semantic_fields/g7_4_semantic_field_lab_acceptance.gd; do
  echo "Running $test_script"
  "$GODOT_EXECUTABLE" --headless --path "$ROOT_DIR" --script "$test_script"
done

SCENE_OUTPUT="$("$GODOT_EXECUTABLE" --headless --path "$ROOT_DIR" --scene res://scenes/labs/procedural/g7_4_semantic_field_lab.tscn --quit-after 20 2>&1)"
printf '%s\n' "$SCENE_OUTPUT"

grep -q 'G7.4 Semantic Field Lab: PASS' <<<"$SCENE_OUTPUT"
grep -q 'samples=561' <<<"$SCENE_OUTPUT"
grep -q 'fields=5' <<<"$SCENE_OUTPUT"
grep -q 'vocabulary_only=6' <<<"$SCENE_OUTPUT"
grep -q 'faces=.*PX' <<<"$SCENE_OUTPUT"
grep -q 'faces=.*PZ' <<<"$SCENE_OUTPUT"

if grep -Eq 'SCRIPT ERROR|Parse Error|Failed to load script' <<<"$SCENE_OUTPUT"; then
  echo "G7.4 semantic field lab reported a script parse/load error" >&2
  exit 1
fi

echo "G7.4 Semantic Field Lab focused gate passed."
