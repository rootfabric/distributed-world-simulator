#!/usr/bin/env bash
set -euo pipefail

GODOT_BIN="${1:-}"
EXPECTED_HEAD="${2:-}"
EXPECTED_GODOT="4.7.1.stable.double.custom_build.a13da4feb"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARTIFACT_ROOT="$ROOT/artifacts/runtime/v0-p7-7-graphical-digging"
mkdir -p "$ARTIFACT_ROOT"

if [[ -z "$GODOT_BIN" || ! -x "$GODOT_BIN" ]]; then
  echo "Exact Godot executable required as first argument." >&2
  exit 2
fi

VERSION="$("$GODOT_BIN" --version 2>&1 | head -n1 | tr -d '\r')"
[[ "$VERSION" == "$EXPECTED_GODOT" ]] || {
  echo "GODOT_IDENTITY_MISMATCH actual=$VERSION expected=$EXPECTED_GODOT" >&2
  exit 3
}

HEAD="$(git -C "$ROOT" rev-parse HEAD)"
TREE="$(git -C "$ROOT" rev-parse 'HEAD^{tree}')"
[[ -z "$EXPECTED_HEAD" || "$HEAD" == "$EXPECTED_HEAD" ]] || {
  echo "P7_7_HEAD_MISMATCH actual=$HEAD expected=$EXPECTED_HEAD" >&2
  exit 4
}

[[ -z "$(git -C "$ROOT" status --porcelain --untracked-files=no)" ]] || {
  echo "P7.7 gate requires clean tracked checkout." >&2
  git -C "$ROOT" status --short
  exit 5
}

fatal_log_check() {
  local log="$1"
  if grep -F -e "SCRIPT ERROR:" -e "Parse Error:" -e "Compile Error:" \
      -e "Failed to instantiate an autoload" -e "Failed to load script" "$log" >/dev/null 2>&1; then
    tail -n 500 "$log" >&2
    return 1
  fi
}

run_contract() {
  local name="$1"
  local script_path="$2"
  local summary="$3"
  local log="$ARTIFACT_ROOT/$name.log"

  "$GODOT_BIN" --headless --path "$ROOT" --log-file "$log" --script "$script_path"
  fatal_log_check "$log"
  grep -F "$summary" "$log" >/dev/null || {
    tail -n 500 "$log" >&2
    echo "Missing PASS summary: $summary" >&2
    return 1
  }
  echo "[V0-P7.7] PASS $name"
}

IMPORT_LOG="$ARTIFACT_ROOT/import.log"
"$GODOT_BIN" --headless --editor --path "$ROOT" --log-file "$IMPORT_LOG" --import
fatal_log_check "$IMPORT_LOG"

run_contract "p7-7-graphical-slice" \
  "res://tests/runtime/test_v0_p7_7_graphical_digging_slice.gd" \
  "V0-P7.7 graphical digging slice: PASS (52 assertions, 0 failures)"

run_contract "p7-7-a-playground" \
  "res://tests/runtime/test_v0_p7_7_a_digging_playground.gd" \
  "V0-P7.7-A Digging Playground: PASS (20 assertions, 0 failures)"

run_contract "p7-7-b-seam-near" \
  "res://tests/runtime/test_v0_p7_7_b_seam_near_single_region.gd" \
  "V0-P7.7-B seam-near single-region: PASS (20 assertions, 0 failures)"

run_contract "mw10-c0-physical-output" \
  "res://tests/matter/transactions/test_mw10_canonical_physical_output.gd" \
  "MW10 canonical physical output: PASS (30 assertions, 0 failures)"

run_contract "mw10-c1-durability" \
  "res://tests/matter/transactions/test_mw10_physical_output_durability.gd" \
  "MW10 physical output durability: PASS (60 assertions, 0 failures)"

run_contract "p7-7-c2-delivery" \
  "res://tests/runtime/test_v0_p7_7_c2_mw10_physical_output_delivery.gd" \
  "V0-P7.7-C2 MW10 physical output to P7.3: PASS (42 assertions, 0 failures)"

run_contract "p7-7-c3-true-ab" \
  "res://tests/runtime/test_v0_p7_7_c3_true_ab_end_to_end.gd" \
  "V0-P7.7-C3 true A+B end-to-end: PASS (61 assertions, 0 failures)"

run_contract "p7-7-d-reservation-conflict" \
  "res://tests/runtime/test_v0_p7_7_d_mw10_reservation_conflict.gd" \
  "V0-P7.7-D MW10 reservation conflict: PASS (31 assertions, 0 failures)"

run_contract "p7-7-e-actor-handoff" \
  "res://tests/runtime/test_v0_p7_7_e_actor_handoff_no_false_mw10.gd" \
  "V0-P7.7-E actor handoff no false MW10: PASS (24 assertions, 0 failures)"

run_contract "p7-6-seam-composition" \
  "res://tests/runtime/test_v0_p7_6_seam_multi_region_composition.gd" \
  "V0-P7.6 seam and multi-region composition: PASS (106 assertions, 0 failures)"

run_contract "mw10-transactions" \
  "res://tests/matter/transactions/test_mw10_cross_region_transactions.gd" \
  "MW10 cross-region Matter transactions: PASS"

run_contract "mw10-process-recovery" \
  "res://tests/matter/transactions/test_mw10_cross_region_processes.gd" \
  "MW10 cross-region process recovery: PASS"

run_contract "mw4" \
  "res://tests/matter/mutation/test_mw4_matter_excavation.gd" \
  "MW4 Matter excavation: PASS"

P7_5_LOG="$ARTIFACT_ROOT/p7-5-subgate.log"
bash "$ROOT/RUN_V0_P7_5_TWO_CLIENT_CONVERGENCE_GATE.sh" "$GODOT_BIN" "$HEAD" >"$P7_5_LOG" 2>&1
fatal_log_check "$P7_5_LOG"
grep -F "V0-P7.5 TWO CLIENT CONVERGENCE GATE GREEN" "$P7_5_LOG" >/dev/null || {
  tail -n 500 "$P7_5_LOG" >&2
  echo "P7.5 subgate did not finish GREEN." >&2
  exit 7
}
echo "[V0-P7.7] PASS p7-5-full-subgate"

git -C "$ROOT" diff --check

[[ -z "$(git -C "$ROOT" status --porcelain --untracked-files=no)" ]] || {
  git -C "$ROOT" status --short
  echo "P7.7 gate changed tracked checkout." >&2
  exit 8
}

echo "V0-P7.7 GRAPHICAL DIGGING GATE GREEN"
echo "EXACT_HEAD=$HEAD"
echo "EXACT_TREE=$TREE"
echo "GODOT=$VERSION"
