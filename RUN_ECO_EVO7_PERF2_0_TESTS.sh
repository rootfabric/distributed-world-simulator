#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
GODOT_BIN="${GODOT_BIN:-${GODOT_DOUBLE_BIN:-godot}}"
EXPECTED="4.7.1.stable.double.custom_build.a13da4feb"

ACTUAL="$("$GODOT_BIN" --version | head -n 1 | tr -d '\r')"
if [[ "$ACTUAL" != "$EXPECTED" ]]; then
  echo "ECO.EVO7 PERF2.0 BLOCKED: expected Godot '$EXPECTED', got '$ACTUAL'" >&2
  exit 2
fi

LOG_ROOT="$ROOT/artifacts/perf2_gate_logs"
mkdir -p "$LOG_ROOT"

run_gate() {
  local name="$1"
  local script="$2"
  local log="$LOG_ROOT/${name//./_}.log"
  echo "PERF2.0 GATE START $name"
  "$GODOT_BIN" --headless --path "$ROOT" --log-file "$log" --script "$script"
  echo "PERF2.0 GATE PASS $name"
}

run_gate "PERF1" "res://tests/ecology/eco_evo7_perf1_generation_profiler_acceptance.gd"
run_gate "STREAM1" "res://tests/ecology/eco_evo7_stream1_generation_stream_acceptance.gd"
run_gate "PERF2.0" "res://tests/ecology/eco_evo7_perf2_measurement_contract_acceptance.gd"

echo "ECO.EVO7 PERF2.0 transitive measurement-contract acceptance: PASS"
