#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-}"

if [[ -z "$GODOT_BIN" ]]; then
  echo "GODOT_BIN is required" >&2
  exit 1
fi

printf '%s\n' '=== G6.3 accepted dependency gate ==='
bash "$ROOT_DIR/RUN_G6_3_RUNTIME_WATER_QUERY_TESTS.sh"

printf '%s\n' '=== G6.4 source / P0 contract gate ==='
"$GODOT_BIN" --headless --path "$ROOT_DIR" --script res://tests/procedural/hydrology/g6_4_casual_visual_river_lab_acceptance.gd

printf '%s\n' '=== G6.4 headless scene smoke ==='
set +e
SCENE_OUTPUT=$("$GODOT_BIN" --headless --path "$ROOT_DIR" --scene res://scenes/labs/procedural/g6_4_casual_visual_river_lab.tscn --quit-after 2 2>&1)
SCENE_STATUS=$?
set -e
printf '%s\n' "$SCENE_OUTPUT"
if [[ $SCENE_STATUS -ne 0 ]]; then
  echo "G6.4 visual river lab headless smoke failed with exit code $SCENE_STATUS" >&2
  exit 1
fi
if grep -Eq '^(SCRIPT ERROR:|ERROR: Failed to load script)' <<<"$SCENE_OUTPUT"; then
  echo "G6.4 visual river lab headless smoke reported a script parse/load error" >&2
  exit 1
fi
if ! grep -Fq 'G6.4 Casual Visual River Lab: PASS' <<<"$SCENE_OUTPUT"; then
  echo "G6.4 visual river lab headless smoke did not emit its explicit PASS marker" >&2
  exit 1
fi

printf '%s\n' 'G6.4 Casual Visual River Lab automated gate passed.'
printf '%s\n' 'Manual graphical observation is still required before G6.4 acceptance.'
