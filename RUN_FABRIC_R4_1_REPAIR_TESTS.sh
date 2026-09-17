#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
: "${GODOT_BIN:?Set GODOT_BIN to canonical Linux double Godot}"
export GODOT_BIN GODOT="$GODOT_BIN" BREAKPOINT_RUNTIME_DISABLED=1
run_godot() {
  local script="$1"
  timeout --kill-after=10s 900s "$GODOT_BIN" --headless --path "$ROOT" --script "res://$script"
}
run_godot tests/research/fabric1/fabric_r4_1_numeric_diagnostics_acceptance.gd
bash RUN_FABRIC_HOLDOUT_R4_G2_TESTS.sh
bash RUN_FABRIC_COMPLEX2_PERF_TESTS.sh
bash RUN_FABRIC_COMPLEX2_CLOSE_TESTS.sh
B06_LOG_DIR="${B06_LOG_DIR:-$ROOT/artifacts/fabric-r4-1-b06-close}" bash RUN_FABRIC_B0_6_CLOSE_TESTS.sh
