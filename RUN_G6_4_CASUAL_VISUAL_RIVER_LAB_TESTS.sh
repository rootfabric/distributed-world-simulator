#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-}"

if [[ -z "$GODOT_BIN" ]]; then
  echo "GODOT_BIN is required" >&2
  exit 1
fi

PREV_BREAKPOINT_RUNTIME_DISABLED="${BREAKPOINT_RUNTIME_DISABLED-__UNSET__}"
export BREAKPOINT_RUNTIME_DISABLED=1
cleanup() {
  if [[ "$PREV_BREAKPOINT_RUNTIME_DISABLED" == "__UNSET__" ]]; then
    unset BREAKPOINT_RUNTIME_DISABLED
  else
    export BREAKPOINT_RUNTIME_DISABLED="$PREV_BREAKPOINT_RUNTIME_DISABLED"
  fi
}
trap cleanup EXIT

printf '%s\n' '=== G6.3 accepted dependency gate ==='
bash "$ROOT_DIR/RUN_G6_3_RUNTIME_WATER_QUERY_TESTS.sh"

printf '%s\n' '=== G6.4 source / P0 / adaptive representation contract gate ==='
"$GODOT_BIN" --headless --path "$ROOT_DIR" --script res://tests/procedural/hydrology/g6_4_casual_visual_river_lab_acceptance.gd

printf '%s\n' '=== G6.4 headless scene + river LOD + G3 detail-recipe smoke ==='
set +e
SCENE_OUTPUT=$("$GODOT_BIN" --headless --path "$ROOT_DIR" --scene res://scenes/labs/procedural/g6_4_casual_visual_river_lab.tscn --quit-after 2 2>&1)
SCENE_STATUS=$?
set -e
printf '%s\n' "$SCENE_OUTPUT"
if [[ $SCENE_STATUS -ne 0 ]]; then
  echo "G6.4 visual river lab headless smoke failed with exit code $SCENE_STATUS" >&2
  exit 1
fi
if grep -Eq 'SCRIPT ERROR:|Parse Error|Failed to load script' <<<"$SCENE_OUTPUT"; then
  echo "G6.4 visual river lab headless smoke reported a script parse/load error" >&2
  exit 1
fi
if ! grep -Fq 'G6.4 Adaptive Macro Surface: PASS' <<<"$SCENE_OUTPUT"; then
  echo "G6.4 adaptive macro surface did not emit its explicit PASS marker" >&2
  exit 1
fi
if ! grep -Eq 'far_triangles=[0-9]+ near_triangles=[0-9]+' <<<"$SCENE_OUTPUT"; then
  echo "G6.4 adaptive macro surface marker did not expose far/near geometry detail" >&2
  exit 1
fi
if ! grep -Fq 'octaves=8' <<<"$SCENE_OUTPUT"; then
  echo "G6.4 fix4 marker did not expose eight-octave diagnostic detail" >&2
  exit 1
fi
if ! grep -Fq 'min_signal_km=4.688' <<<"$SCENE_OUTPUT"; then
  echo "G6.4 fix4 marker did not expose ~4.7 km minimum source wavelength" >&2
  exit 1
fi
if ! grep -Fq 'G6.4 Casual Visual River Lab: PASS' <<<"$SCENE_OUTPUT"; then
  echo "G6.4 visual river lab headless smoke did not emit its explicit PASS marker" >&2
  exit 1
fi
if ! grep -Eq 'max_lod=[0-9]+' <<<"$SCENE_OUTPUT"; then
  echo "G6.4 PASS marker did not expose active max LOD" >&2
  exit 1
fi
if ! grep -Eq 'river_lod=[0-9]+\.\.[0-9]+' <<<"$SCENE_OUTPUT"; then
  echo "G6.4 PASS marker did not expose river representation LOD range" >&2
  exit 1
fi

printf '%s\n' 'G6.4 Casual Visual River Lab fix4 automated gate passed.'
printf '%s\n' 'Headless proof covers G2 selection, river sampling, G3 triangle refinement, and the 8-octave diagnostic detail recipe.'
printf '%s\n' 'BreakpointRuntimeBridge is disabled for this standalone gate.'
printf '%s\n' 'G6.4 manual graphical acceptance is already recorded; this rerun verifies automated evidence.'