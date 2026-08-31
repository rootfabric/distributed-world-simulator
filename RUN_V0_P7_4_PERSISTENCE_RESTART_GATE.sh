#!/usr/bin/env bash
set -euo pipefail

GODOT_BIN="${1:-}"
EXPECTED_HEAD="${2:-}"
EXPECTED_GODOT="4.7.1.stable.double.custom_build.a13da4feb"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARTIFACT_ROOT="$ROOT/artifacts/runtime/v0-p7-4-persistence-restart"
TEST_HOME="$ARTIFACT_ROOT/user-home"
mkdir -p "$ARTIFACT_ROOT"
rm -rf "$TEST_HOME"
mkdir -p "$TEST_HOME/data" "$TEST_HOME/config" "$TEST_HOME/cache"

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
[[ -z "$EXPECTED_HEAD" || "$HEAD" == "$EXPECTED_HEAD" ]] || {
  echo "P7_4_HEAD_MISMATCH actual=$HEAD expected=$EXPECTED_HEAD" >&2
  exit 4
}
[[ -z "$(git -C "$ROOT" status --porcelain --untracked-files=no)" ]] || {
  echo "P7.4 gate requires clean tracked checkout." >&2
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
  local script="$2"
  local summary="$3"
  shift 3
  local log="$ARTIFACT_ROOT/$name.log"
  "$GODOT_BIN" --headless --path "$ROOT" --log-file "$log" --script "$script" "$@"
  fatal_log_check "$log"
  grep -F "$summary" "$log" >/dev/null || {
    tail -n 500 "$log" >&2
    echo "Missing PASS summary: $summary" >&2
    return 1
  }
  echo "[V0-P7.4] PASS $name"
}

run_restart_phase() {
  local phase="$1"
  local log="$ARTIFACT_ROOT/p7-4-$phase.log"
  HOME="$TEST_HOME" \
  XDG_DATA_HOME="$TEST_HOME/data" \
  XDG_CONFIG_HOME="$TEST_HOME/config" \
  XDG_CACHE_HOME="$TEST_HOME/cache" \
  APPDATA="$TEST_HOME/data" \
  LOCALAPPDATA="$TEST_HOME/data" \
    "$GODOT_BIN" --headless --path "$ROOT" --log-file "$log" \
      --script res://tests/runtime/test_v0_p7_4_persistence_restart_composition.gd \
      -- "--phase=$phase"
  fatal_log_check "$log"
  grep -F "V0-P7.4 $phase: PASS" "$log" >/dev/null || {
    tail -n 500 "$log" >&2
    echo "Missing P7.4 phase PASS: $phase" >&2
    return 1
  }
  echo "[V0-P7.4] PASS restart-$phase"
}

IMPORT_LOG="$ARTIFACT_ROOT/import.log"
"$GODOT_BIN" --headless --editor --path "$ROOT" --log-file "$IMPORT_LOG" --import
fatal_log_check "$IMPORT_LOG"

run_restart_phase "seed"
run_restart_phase "recover-deliver"
run_restart_phase "recover-replay"

run_contract "p7-3-material-delivery" \
  "res://tests/runtime/test_v0_p7_3_material_batch_to_item_graph.gd" \
  "V0-P7.3 material batch to Item Graph: PASS (116 assertions, 0 failures)"
run_contract "p7-2-bubble" \
  "res://tests/matter/product/test_v0_p7_2_lunar_matter_bubble.gd" \
  "V0-P7.2 lunar Matter bubble: PASS (53 assertions, 0 failures)"
run_contract "p7-2-seam" \
  "res://tests/runtime/test_v0_p7_2_lunar_surface_seam.gd" \
  "V0-P7.2 lunar surface seam: PASS (50 assertions, 0 failures)"
run_contract "p7-1-authority" \
  "res://tests/runtime/test_v0_p7_1_matter_command_authority_gate.gd" \
  "V0-P7.1 authority gate: PASS (83 assertions, 0 failures)"
run_contract "p7-1-tool-to-mw4" \
  "res://tests/runtime/test_v0_p7_1_tool_to_mw4_adapter.gd" \
  "V0-P7.1 Tool->MW4 integration: PASS (30 assertions, 0 failures)"
run_contract "p5-mining-tool" \
  "res://tests/runtime/test_v0_p5_mining_tool_gate.gd" \
  "V0-P5 mining tool gate: 36 assertions, 0 failures"
run_contract "p3-resource-domain" \
  "res://tests/runtime/test_v0_p3_resource_mining_domain.gd" \
  "V0-P3 resource/mining domain: 79 assertions, 0 failures"
run_contract "p3-aggregate-recovery" \
  "res://tests/runtime/test_v0_p3_resource_mining_aggregate_recovery.gd" \
  "V0-P3 aggregate resource recovery: 33 assertions, 0 failures"
run_contract "m6-recovery-contracts" \
  "res://tests/runtime/test_m6_dedicated_recovery_contracts.gd" \
  "M6 dedicated recovery contracts: 126 assertions, 0 failures"
run_contract "m6-recovery-processes" \
  "res://tests/runtime/test_m6_dedicated_recovery_processes.gd" \
  "M6 dedicated recovery processes: 128 assertions, 0 failures"
run_contract "mw4" \
  "res://tests/matter/mutation/test_mw4_matter_mutations.gd" \
  "MW4 matter mutations: PASS"
run_contract "mw5" \
  "res://tests/matter/persistence/test_mw5_matter_persistence.gd" \
  "MW5 matter persistence: PASS"
run_contract "mw6" \
  "res://tests/matter/network/test_mw6_matter_network_replication.gd" \
  "MW6 matter network authority: PASS"

[[ -z "$(git -C "$ROOT" status --porcelain --untracked-files=no)" ]] || {
  git -C "$ROOT" status --short
  echo "P7.4 gate changed tracked checkout." >&2
  exit 6
}

echo "V0-P7.4 PERSISTENCE RESTART COMPOSITION GATE GREEN"
echo "EXACT_HEAD=$HEAD"
echo "GODOT=$VERSION"
