#!/usr/bin/env bash
set -euo pipefail

GODOT_BIN="${1:-}"
EXPECTED_HEAD="${2:-}"
EXPECTED_GODOT="4.7.1.stable.double.custom_build.a13da4feb"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARTIFACT_ROOT="$ROOT/artifacts/runtime/v0-p7-2-lunar-matter-bubble"
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
[[ -z "$EXPECTED_HEAD" || "$HEAD" == "$EXPECTED_HEAD" ]] || {
  echo "P7_2_HEAD_MISMATCH actual=$HEAD expected=$EXPECTED_HEAD" >&2
  exit 4
}
[[ -z "$(git -C "$ROOT" status --porcelain)" ]] || {
  echo "P7.2 gate requires clean tracked checkout." >&2
  git -C "$ROOT" status --short
  exit 5
}

fatal_log_check() {
  local log="$1"
  if grep -F -e "SCRIPT ERROR:" -e "Parse Error:" -e "Compile Error:"     -e "Failed to instantiate an autoload" -e "Failed to load script" "$log" >/dev/null 2>&1; then
    tail -n 500 "$log" >&2
    return 1
  fi
}

run_contract() {
  local name="$1"
  local script="$2"
  local summary="$3"
  local log="$ARTIFACT_ROOT/$name.log"
  "$GODOT_BIN" --headless --path "$ROOT" --log-file "$log" --script "$script"
  fatal_log_check "$log"
  grep -F "$summary" "$log" >/dev/null || {
    tail -n 500 "$log" >&2
    echo "Missing PASS summary: $summary" >&2
    return 1
  }
  echo "[V0-P7.2] PASS $name"
}

IMPORT_LOG="$ARTIFACT_ROOT/import.log"
"$GODOT_BIN" --headless --editor --path "$ROOT" --log-file "$IMPORT_LOG" --import
fatal_log_check "$IMPORT_LOG"

run_contract "p7-2-bubble"   "res://tests/matter/product/test_v0_p7_2_lunar_matter_bubble.gd"   "V0-P7.2 lunar Matter bubble: PASS"
run_contract "p7-2-seam"   "res://tests/runtime/test_v0_p7_2_lunar_surface_seam.gd"   "V0-P7.2 lunar surface seam: PASS"
run_contract "p7-1-authority"   "res://tests/runtime/test_v0_p7_1_matter_command_authority_gate.gd"   "V0-P7.1 authority gate: PASS"
run_contract "p7-1-tool-to-mw4"   "res://tests/runtime/test_v0_p7_1_tool_to_mw4_adapter.gd"   "V0-P7.1 Tool->MW4 integration: PASS"
run_contract "mw4"   "res://tests/matter/mutation/test_mw4_matter_mutations.gd"   "MW4 matter mutations: PASS"
run_contract "mw5"   "res://tests/matter/persistence/test_mw5_matter_persistence.gd"   "MW5 matter persistence: PASS"
run_contract "mw6"   "res://tests/matter/network/test_mw6_matter_network_replication.gd"   "MW6 matter network authority: PASS"

[[ -z "$(git -C "$ROOT" status --porcelain)" ]] || {
  git -C "$ROOT" status --short
  echo "P7.2 gate changed tracked checkout." >&2
  exit 6
}

echo "V0-P7.2 BOUNDED LUNAR MATTER BUBBLE GATE GREEN"
echo "EXACT_HEAD=$HEAD"
echo "GODOT=$VERSION"
