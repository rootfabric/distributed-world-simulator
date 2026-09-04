#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
GODOT_BIN="${GODOT_BIN:-${GODOT_DOUBLE_BIN:-godot}}"
EXPECTED="4.7.1.stable.double.custom_build.a13da4feb"
ACTUAL="$($GODOT_BIN --version | head -n 1 | tr -d '\r')"
if [[ "$ACTUAL" != "$EXPECTED" ]]; then
  echo "ECO.EVO7 VIS5.4 BLOCKED: expected Godot '$EXPECTED', got '$ACTUAL'" >&2
  exit 2
fi
export BREAKPOINT_RUNTIME_DISABLED=1
export GODOT_BIN
if [[ ! -f "$ROOT/.godot/uid_cache.bin" ]]; then
  "$GODOT_BIN" --headless --editor --path "$ROOT" --import
fi
echo "=== ECO VIS5.3 closed predecessor regression ==="
bash "$ROOT/RUN_ECO_EVO7_VIS5_3_TESTS.sh"
echo "=== ECO VIS5.4 composition LOD / streaming focused acceptance ==="
"$GODOT_BIN" --headless --path "$ROOT" --script res://tests/ecology/eco_evo7_vis5_4_composition_lod_streaming_gate_acceptance.gd
echo "ECO.EVO7 VIS5.4 Composition LOD / Streaming Local Gate candidate: PASS"
