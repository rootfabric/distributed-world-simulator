#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
GODOT_BIN="${GODOT_BIN:-${GODOT_DOUBLE_BIN:-godot}}"
EXPECTED="4.7.1.stable.double.custom_build.a13da4feb"
ACTUAL="$("$GODOT_BIN" --version | head -n 1 | tr -d '\r')"
if [[ "$ACTUAL" != "$EXPECTED" ]]; then
  echo "ECO.EVO7 VIS4.1 BLOCKED: expected Godot '$EXPECTED', got '$ACTUAL'" >&2
  exit 2
fi
export BREAKPOINT_RUNTIME_DISABLED=1
if [[ ! -f "$ROOT/.godot/uid_cache.bin" ]]; then
  "$GODOT_BIN" --headless --editor --path "$ROOT" --import
fi

./RUN_ECO_EVO7_VIS4_0_TESTS.sh
"$GODOT_BIN" --headless --path "$ROOT" --script res://tests/ecology/eco_evo7_ls34_local_competition_acceptance.gd
"$GODOT_BIN" --headless --path "$ROOT" --script res://tests/ecology/eco_evo7_ls36_rule_workbench_acceptance.gd
"$GODOT_BIN" --headless --path "$ROOT" --script res://tests/ecology/eco_evo7_vis4_1_source_bound_morphology_evidence_acceptance.gd
./RUN_ECO_EVO7_VIS2_TESTS.sh

echo "ECO.EVO7 VIS4.1 Source-Bound Morphology Evidence candidate: PASS"
