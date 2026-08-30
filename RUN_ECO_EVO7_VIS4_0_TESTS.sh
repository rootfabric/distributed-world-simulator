#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
GODOT_BIN="${GODOT_BIN:-${GODOT_DOUBLE_BIN:-godot}}"
EXPECTED="4.7.1.stable.double.custom_build.a13da4feb"
ACTUAL="$("$GODOT_BIN" --version | head -n 1 | tr -d '\r')"
if [[ "$ACTUAL" != "$EXPECTED" ]]; then
  echo "ECO.EVO7 VIS4.0 BLOCKED: expected Godot '$EXPECTED', got '$ACTUAL'" >&2
  exit 2
fi
export BREAKPOINT_RUNTIME_DISABLED=1
if [[ ! -f "$ROOT/.godot/uid_cache.bin" ]]; then
  "$GODOT_BIN" --headless --editor --path "$ROOT" --import
fi
"$GODOT_BIN" --headless --path "$ROOT" --script res://tests/research/ecology/eco_evo7_fff2_morphology_evolution_acceptance.gd
"$GODOT_BIN" --headless --path "$ROOT" --script res://tests/research/ecology/eco_ph2_environment_coupled_development_acceptance.gd
"$GODOT_BIN" --headless --path "$ROOT" --script res://tests/ecology/eco_evo7_vis4_0_truth_contract_audit_acceptance.gd
echo "ECO.EVO7 VIS4.0 Truth / Contract Audit candidate: PASS"
