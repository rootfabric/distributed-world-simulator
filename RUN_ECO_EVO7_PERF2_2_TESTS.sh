#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

GODOT_BIN="${GODOT_BIN:-${GODOT_DOUBLE_BIN:-godot}}"
EXPECTED_GODOT="4.7.1.stable.double.custom_build.a13da4feb"
EXPECTED_BASE="7044c13e8cd9b036f318192ba0d62c6f3393fb60"
EXPECTED_CONTRACT_BLOB="b076784f6b4016a0191e937c4e6ada1fe90c783b"
CONTRACT_PATH="config/ecology/eco-evo7-perf2-measurement-contract.v1.json"

ACTUAL_GODOT="$("$GODOT_BIN" --version | head -n 1 | tr -d '\r')"
if [[ "$ACTUAL_GODOT" != "$EXPECTED_GODOT" ]]; then
  echo "ECO.EVO7 PERF2.2 BLOCKED: expected Godot '$EXPECTED_GODOT', got '$ACTUAL_GODOT'" >&2
  exit 2
fi

HEAD="$(git rev-parse HEAD)"
TREE="$(git rev-parse 'HEAD^{tree}')"

if ! git merge-base --is-ancestor "$EXPECTED_BASE" "$HEAD"; then
  echo "PERF2.2 BASE MISMATCH: accepted PERF2.1 control tip is not an ancestor" >&2
  exit 3
fi

CONTRACT_BLOB="$(git rev-parse "HEAD:$CONTRACT_PATH")"
if [[ "$CONTRACT_BLOB" != "$EXPECTED_CONTRACT_BLOB" ]]; then
  echo "PERF2.2 CONTRACT DRIFT: expected $EXPECTED_CONTRACT_BLOB got $CONTRACT_BLOB" >&2
  exit 4
fi
git diff --quiet -- "$CONTRACT_PATH" || {
  echo "PERF2.2 CONTRACT WORKTREE DRIFT" >&2
  exit 5
}

PROTECTED_DIFF="$(git diff --name-only "$EXPECTED_BASE...$HEAD" -- \
  scripts/ecology/shadow \
  scripts/ecology/perf/eco_evo7_stream1_generation_stream_executor_v1.gd \
  scripts/ecology/perf/eco_evo7_stream1_route_kernel_v1.gd \
  scripts/ecology/perf/eco_evo7_perf2_measurement_contract_v1.gd \
  scripts/ecology/perf/eco_evo7_perf2_measurement_probe_v1.gd \
  scripts/ecology/perf/eco_evo7_perf21_generation_profiler_v1.gd)"

if [[ -n "$PROTECTED_DIFF" ]]; then
  echo "PERF2.2 PROTECTED RUNTIME DIFF FAIL" >&2
  printf '%s\n' "$PROTECTED_DIFF" >&2
  exit 6
fi

CPU_MODEL="$(lscpu | awk -F: '/Model name/ {sub(/^[ \t]+/,"",$2); print $2; exit}')"
HOST_DESCRIPTOR="$(printf '%s|%s|%s|%s' 'linux' "$(uname -srmo)" "$CPU_MODEL" "$(nproc)")"
HOST_FINGERPRINT="$(printf '%s' "$HOST_DESCRIPTOR" | sha256sum | awk '{print $1}')"

export ECO_PERF2_TARGET_HEAD="$HEAD"
export ECO_PERF2_TARGET_TREE="$TREE"
export ECO_PERF2_HOST_FINGERPRINT="$HOST_FINGERPRINT"
export BREAKPOINT_RUNTIME_DISABLED=1

echo "PERF2.2 exact target HEAD=$HEAD"
echo "PERF2.2 exact target TREE=$TREE"
echo "PERF2.2 accepted predecessor=$EXPECTED_BASE"
echo "PERF2.2 Godot=$ACTUAL_GODOT"
echo "PERF2.2 frozen contract blob=$CONTRACT_BLOB"
echo "PERF2.2 host fingerprint=$HOST_FINGERPRINT"
echo "PERF2.2 protected runtime diff=PASS"

LOG_ROOT="$ROOT/artifacts/perf22_gate_logs"
mkdir -p "$LOG_ROOT"

echo "PERF2.2 fresh import START"
"$GODOT_BIN" --headless --import --path "$ROOT" \
  2>&1 | tee "$LOG_ROOT/import.log"
echo "PERF2.2 fresh import PASS"

run_gate() {
  local name="$1"
  local script="$2"
  local log="$LOG_ROOT/${name//./_}.log"
  echo "PERF2.2 GATE START $name"
  "$GODOT_BIN" --headless --path "$ROOT" --log-file "$log" --script "$script" \
    2>&1 | tee "$LOG_ROOT/${name//./_}.console.log"
  echo "PERF2.2 GATE PASS $name"
}

run_gate "PERF1" "res://tests/ecology/eco_evo7_perf1_generation_profiler_acceptance.gd"
run_gate "STREAM1" "res://tests/ecology/eco_evo7_stream1_generation_stream_acceptance.gd"
run_gate "PERF2.0" "res://tests/ecology/eco_evo7_perf2_measurement_contract_acceptance.gd"
run_gate "PERF2.1" "res://tests/ecology/eco_evo7_perf21_generation_profiling_acceptance.gd"
run_gate "PERF2.2" "res://tests/ecology/eco_evo7_perf22_working_set_memory_acceptance.gd"

REPORT="$ROOT/artifacts/perf2/perf2-2-working-set-memory-r1.json"
if [[ ! -s "$REPORT" ]]; then
  echo "PERF2.2 report missing: $REPORT" >&2
  exit 7
fi

python3 - "$REPORT" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    r = json.load(f)

assert r["schema"] == "distributed_world_simulator.ecology.evo7_perf2_2.working_set_memory_report.v1"
assert r["revision"] == "ECO.EVO7-PERF2.2-R1"
assert len(r["working_set_rows"]) == 4
assert len(r["memory_rows"]) == 4
assert len(r["comparisons"]) == 3
assert r["memory_semantics"]["engine_static_peak_cross_config_comparable"] is False
assert r["memory_semantics"]["memory_reduction_claim_allowed"] is False

print("PERF2_2_WORKING_SET_ROWS=4")
print("PERF2_2_MEMORY_ROWS=4")
print("PERF2_2_COMPARISONS=3")
print("PERF2_2_REPORT_HASH=" + r["report_hash"])

for c in sorted(r["comparisons"], key=lambda x: int(x["stream_chunk_size"])):
    assert int(c["exact_pairs"]) == 3
    assert c["working_set_bound_claim"] is True
    assert c["memory_reduction_claim"] is False
    assert c["optimization_claim"] is False
    print(
        "PERF2_2_PROFILE "
        f"chunk={int(c['stream_chunk_size'])} "
        f"parent_reduction={float(c['parent_record_reduction_factor_serial_over_stream']):.6f} "
        f"candidate_reduction={float(c['candidate_record_reduction_factor_serial_over_stream']):.6f} "
        f"proxy_reduction={float(c['record_proxy_reduction_factor_serial_over_stream']):.6f} "
        f"engine_static_ratio={float(c['engine_static_end_ratio_serial_over_stream']):.6f}"
    )
PY

FINAL_HEAD="$(git rev-parse HEAD)"
FINAL_TREE="$(git rev-parse 'HEAD^{tree}')"
[[ "$FINAL_HEAD" == "$HEAD" ]] || {
  echo "PERF2.2 HEAD moved: $FINAL_HEAD != $HEAD" >&2
  exit 8
}
[[ "$FINAL_TREE" == "$TREE" ]] || {
  echo "PERF2.2 TREE moved: $FINAL_TREE != $TREE" >&2
  exit 9
}

TRACKED="$(git status --porcelain --untracked-files=no)"
if [[ -n "$TRACKED" ]]; then
  echo "PERF2.2 tracked worktree changed during gate" >&2
  printf '%s\n' "$TRACKED" >&2
  exit 10
fi

echo "PERF2.2 final HEAD=$FINAL_HEAD"
echo "PERF2.2 final TREE=$FINAL_TREE"
echo "PERF2.2 tracked worktree clean=YES"
echo "ECO.EVO7 PERF2.2 transitive working-set/memory R1 acceptance: PASS"
