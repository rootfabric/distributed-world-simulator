#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

GODOT_BIN="${GODOT_BIN:-${GODOT_DOUBLE_BIN:-godot}}"
EXPECTED="4.7.1.stable.double.custom_build.a13da4feb"
ACTUAL="$("$GODOT_BIN" --version | head -n 1 | tr -d '\r')"

if [[ "$ACTUAL" != "$EXPECTED" ]]; then
  echo "ECO.EVO7 VIS5.0 BLOCKED: expected Godot '$EXPECTED', got '$ACTUAL'" >&2
  exit 2
fi

export BREAKPOINT_RUNTIME_DISABLED=1
export GODOT_BIN

if [[ ! -f "$ROOT/.godot/uid_cache.bin" ]]; then
  "$GODOT_BIN" --headless --editor --path "$ROOT" --import
fi

echo "=== ECO VIS4.9 closed predecessor regression ==="
"$ROOT/RUN_ECO_EVO7_VIS4_9_TESTS.sh"

echo "=== ECO VIS5.0 terrain / ecosystem composition contract audit ==="
"$GODOT_BIN" --headless --path "$ROOT" --script res://tests/ecology/eco_evo7_vis5_0_terrain_ecosystem_composition_contract_acceptance.gd

echo "ECO.EVO7 VIS5.0 Terrain / Ecosystem Composition Contract Audit candidate: PASS"
