#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
GODOT_BIN="${GODOT_BIN:-${GODOT_DOUBLE_BIN:-godot}}"
EXPECTED="4.7.1.stable.double.custom_build.a13da4feb"
SCENE="res://scenes/labs/ecology/eco_evo7_vis3_planet_biome_viewer.tscn"
ACTUAL="$($GODOT_BIN --version | head -n 1 | tr -d '\r')"
if [[ "$ACTUAL" != "$EXPECTED" ]]; then
  echo "ECO.EVO7 VIS3 BLOCKED: expected Godot '$EXPECTED', got '$ACTUAL'" >&2
  exit 2
fi
echo "ECO.EVO7 VIS3 launching explicit scene: $SCENE"
exec "$GODOT_BIN" --path "$ROOT" --resolution 1600x900 --scene "$SCENE"
