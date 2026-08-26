#!/usr/bin/env bash
set -euo pipefail
GODOT_BIN="${GODOT_BIN:-${GODOT_DOUBLE_BIN:-godot}}"
EXPECTED="4.7.1.stable.double.custom_build.a13da4feb"
ACTUAL="$($GODOT_BIN --version | head -n 1 | tr -d '\r')"
if [[ "$ACTUAL" != "$EXPECTED" ]]; then
  echo "ECO.EVO7 LIVE SHADOW BLOCKED: expected Godot '$EXPECTED', got '$ACTUAL'" >&2
  exit 2
fi
"$GODOT_BIN" --headless --path . --script res://tests/ecology/eco_evo7_live_world_shadow_acceptance.gd
"$GODOT_BIN" --headless --path . --script res://tests/ecology/eco_evo7_live_world_shadow_runtime_smoke.gd
