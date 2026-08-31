#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

GODOT_BIN="${GODOT_BIN:-${GODOT_DOUBLE_BIN:-godot}}"
EXPECTED="4.7.1.stable.double.custom_build.a13da4feb"
ACTUAL="$("$GODOT_BIN" --version | head -n 1 | tr -d '\r')"

if [[ "$ACTUAL" != "$EXPECTED" ]]; then
  echo "ECO.EVO7 VIS4.4 BLOCKED: expected Godot '$EXPECTED', got '$ACTUAL'" >&2
  exit 2
fi

export GODOT_BIN
export GODOT_DOUBLE_BIN="$GODOT_BIN"
export BREAKPOINT_RUNTIME_DISABLED=1

if [[ ! -f "$ROOT/.godot/uid_cache.bin" ]]; then
  "$GODOT_BIN" --headless --editor --path "$ROOT" --import
fi

echo "=== ECO VIS4.3 predecessor regression ==="
bash ./RUN_ECO_EVO7_VIS4_3_TESTS.sh

echo "=== ECO PLAY0 regression ==="
"$GODOT_BIN" --headless --path "$ROOT"   --script res://tests/ecology/eco_evo7_play0_live_planet_playground_acceptance.gd

echo "=== ECO VIS4.4 PLAY0.MORPH focused acceptance ==="
"$GODOT_BIN" --headless --path "$ROOT"   --script res://tests/ecology/eco_evo7_vis4_4_play0_morph_acceptance.gd

echo "ECO.EVO7 VIS4.4 PLAY0.MORPH candidate: PASS"
