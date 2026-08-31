#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

GODOT_BIN="${GODOT_BIN:-${GODOT_DOUBLE_BIN:-godot}}"
EXPECTED="4.7.1.stable.double.custom_build.a13da4feb"
ACTUAL="$("$GODOT_BIN" --version | head -n 1 | tr -d '\r')"
if [[ "$ACTUAL" != "$EXPECTED" ]]; then
  echo "ECO.EVO7 VIS4.3 BLOCKED: expected Godot '$EXPECTED', got '$ACTUAL'" >&2
  exit 2
fi

export BREAKPOINT_RUNTIME_DISABLED=1
if [[ ! -f "$ROOT/.godot/uid_cache.bin" ]]; then
  "$GODOT_BIN" --headless --editor --path "$ROOT" --import
fi

bash ./RUN_ECO_EVO7_VIS4_2_TESTS.sh

for script in   res://tests/research/ecology/eco_ph5_render_materialization_acceptance.gd   res://tests/research/ecology/eco_ph5_s2_3d_materialization_acceptance.gd   res://tests/research/ecology/eco_ph5_s3_multiscale_acceptance.gd   res://tests/research/ecology/eco_ph5_s3_multiscale_materialization_acceptance.gd   res://tests/research/ecology/eco_ph5_s4_representation_robustness.gd   res://tests/research/ecology/eco_ph5_s4_multiscale_matrix_acceptance.gd
do
  "$GODOT_BIN" --headless --path "$ROOT" --script "$script"
done

"$GODOT_BIN" --headless --path "$ROOT" --script res://tests/ecology/eco_evo7_vis4_3_exact_ph5_bridge_acceptance.gd

echo "ECO.EVO7 VIS4.3 Exact Live Phenotype -> PH5 Bridge candidate: PASS"
