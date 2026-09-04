#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

GODOT_BIN="${GODOT_BIN:-${GODOT_DOUBLE_BIN:-godot}}"
EXPECTED_GODOT="4.7.1.stable.double.custom_build.a13da4feb"
EXPECTED_BASE="922b8b377faf19e36e58cf111c5dc917e83e09e1"
EXPECTED_CONTRACT_BLOB="b076784f6b4016a0191e937c4e6ada1fe90c783b"
CONTRACT_PATH="config/ecology/eco-evo7-perf2-measurement-contract.v1.json"

ACTUAL_GODOT="$("$GODOT_BIN" --version | head -n 1 | tr -d '\r')"
if [[ "$ACTUAL_GODOT" != "$EXPECTED_GODOT" ]]; then
  echo "ECO.EVO7 PERF2.3 BLOCKED: expected Godot '$EXPECTED_GODOT', got '$ACTUAL_GODOT'" >&2
  exit 2
fi

HEAD="$(git rev-parse HEAD)"
TREE="$(git rev-parse 'HEAD^{tree}')"

if ! git merge-base --is-ancestor "$EXPECTED_BASE" "$HEAD"; then
  echo "PERF2.3 BASE MISMATCH: accepted PERF2.2 control tip is not an ancestor" >&2
  exit 3
fi

CONTRACT_BLOB="$(git rev-parse "HEAD:$CONTRACT_PATH")"
if [[ "$CONTRACT_BLOB" != "$EXPECTED_CONTRACT_BLOB" ]]; then
  echo "PERF2.3 CONTRACT DRIFT: expected $EXPECTED_CONTRACT_BLOB got $CONTRACT_BLOB" >&2
  exit 4
fi

PROTECTED_DIFF="$(git diff --name-only "$EXPECTED_BASE...$HEAD" -- \
  scripts/ecology/shadow \
  scripts/ecology/perf/eco_evo7_stream1_generation_stream_executor_v1.gd \
  scripts/ecology/perf/eco_evo7_stream1_route_kernel_v1.gd \
  scripts/ecology/perf/eco_evo7_perf2_measurement_contract_v1.gd \
  scripts/ecology/perf/eco_evo7_perf2_measurement_probe_v1.gd \
  scripts/ecology/perf/eco_evo7_perf21_generation_profiler_v1.gd \
  scripts/ecology/perf/eco_evo7_perf22_working_set_memory_profiler_v1.gd)"

if [[ -n "$PROTECTED_DIFF" ]]; then
  echo "PERF2.3 PROTECTED PREDECESSOR DIFF FAIL" >&2
  printf '%s\n' "$PROTECTED_DIFF" >&2
  exit 5
fi

CPU_MODEL="$(lscpu | awk -F: '/Model name/ {sub(/^[ \t]+/,"",$2); print $2; exit}')"
HOST_DESCRIPTOR="$(printf '%s|%s|%s|%s' 'linux' "$(uname -srmo)" "$CPU_MODEL" "$(nproc)")"
HOST_FINGERPRINT="$(printf '%s' "$HOST_DESCRIPTOR" | sha256sum | awk '{print $1}')"

export ECO_PERF2_TARGET_HEAD="$HEAD"
export ECO_PERF2_TARGET_TREE="$TREE"
export ECO_PERF2_HOST_FINGERPRINT="$HOST_FINGERPRINT"
export BREAKPOINT_RUNTIME_DISABLED=1

echo "PERF2.3 exact target HEAD=$HEAD"
echo "PERF2.3 exact target TREE=$TREE"
echo "PERF2.3 accepted predecessor=$EXPECTED_BASE"
echo "PERF2.3 Godot=$ACTUAL_GODOT"
echo "PERF2.3 frozen contract blob=$CONTRACT_BLOB"
echo "PERF2.3 host fingerprint=$HOST_FINGERPRINT"
echo "PERF2.3 protected predecessor diff=PASS"

LOG_ROOT="$ROOT/artifacts/perf23_gate_logs"
mkdir -p "$LOG_ROOT"

echo "PERF2.3 fresh import START"
"$GODOT_BIN" --headless --import --path "$ROOT" 2>&1 | tee "$LOG_ROOT/import.log"
echo "PERF2.3 fresh import PASS"

run_gate() {
  local name="$1"
  local script="$2"
  local stem="${name//./_}"
  echo "PERF2.3 GATE START $name"
  "$GODOT_BIN" --headless --path "$ROOT" \
    --log-file "$LOG_ROOT/${stem}.godot.log" \
    --script "$script" \
    2>&1 | tee "$LOG_ROOT/${stem}.console.log"
  echo "PERF2.3 GATE PASS $name"
}

run_gate "PERF1"   "res://tests/ecology/eco_evo7_perf1_generation_profiler_acceptance.gd"
run_gate "STREAM1" "res://tests/ecology/eco_evo7_stream1_generation_stream_acceptance.gd"
run_gate "PERF2.0" "res://tests/ecology/eco_evo7_perf2_measurement_contract_acceptance.gd"
run_gate "PERF2.1" "res://tests/ecology/eco_evo7_perf21_generation_profiling_acceptance.gd"
run_gate "PERF2.2" "res://tests/ecology/eco_evo7_perf22_working_set_memory_acceptance.gd"
run_gate "PERF2.3" "res://tests/ecology/eco_evo7_perf23_simulation_scaling_acceptance.gd"

REPORT="$ROOT/artifacts/perf2/perf2-3-simulation-scaling-r1.json"
if [[ ! -s "$REPORT" ]]; then
  echo "PERF2.3 report missing: $REPORT" >&2
  exit 6
fi

python3 - "$REPORT" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    r = json.load(f)

assert r["schema"] == "distributed_world_simulator.ecology.evo7_perf2_3.simulation_scaling_report.v1"
assert r["revision"] == "ECO.EVO7-PERF2.3-R1"
assert len(r["samples"]) == 36
assert len(r["scaling_points"]) == 12
assert len(r["comparisons"]) == 9
assert len(r["trends"]) == 4
assert len(r["crossovers"]) == 3
assert r["scale_policy"]["precondition_generations"] == [2, 12, 22]
assert int(r["scale_policy"]["total_generation_advances"]) == 864
assert r["claims"]["optimization_claim"] is False
assert r["claims"]["memory_reduction_claim"] is False

pairs = sum(int(c["exact_pairs"]) for c in r["comparisons"])
assert pairs == 27

print("PERF2_3_SAMPLES=36")
print("PERF2_3_SCALING_POINTS=12")
print("PERF2_3_COMPARISONS=9")
print("PERF2_3_TRENDS=4")
print("PERF2_3_CROSSOVERS=3")
print("PERF2_3_EXACT_PAIRS=27/27")
print("PERF2_3_REPORT_HASH=" + r["report_hash"])

for c in r["comparisons"]:
    print(
        "PERF2_3_PROFILE "
        f"scale={c['scale_id']} "
        f"chunk={int(c['stream_chunk_size'])} "
        f"parents={float(c['serial_parent_p50']):.0f} "
        f"candidates={float(c['serial_candidate_p50']):.0f} "
        f"wall_ratio={float(c['observed_wall_ratio_serial_over_stream']):.6f} "
        f"generation_ratio={float(c['observed_generation_ratio_serial_over_stream']):.6f} "
        f"proxy_reduction={float(c['record_proxy_reduction_factor_serial_over_stream']):.6f} "
        f"faster={c['observed_faster_side']}"
    )

for t in r["trends"]:
    print(
        "PERF2_3_TREND "
        f"config={t['configuration_id']} "
        f"population_growth={float(t['population_growth_factor']):.6f} "
        f"wall_growth={float(t['wall_growth_factor']):.6f} "
        f"generation_growth={float(t['generation_time_growth_factor']):.6f} "
        f"proxy_growth={float(t['record_proxy_growth_factor']):.6f}"
    )

for x in r["crossovers"]:
    print(
        "PERF2_3_CROSSOVER "
        f"chunk={int(x['stream_chunk_size'])} "
        f"observed={str(bool(x['crossover_observed'])).lower()} "
        f"transition={x['first_observed_transition'] or 'NONE'} "
        f"ratios={','.join(f'{float(v):.6f}' for v in x['wall_ratios_serial_over_stream'])}"
    )
PY

FINAL_HEAD="$(git rev-parse HEAD)"
FINAL_TREE="$(git rev-parse 'HEAD^{tree}')"

if [[ "$FINAL_HEAD" != "$HEAD" ]]; then
  echo "PERF2.3 HEAD moved during gate: $FINAL_HEAD != $HEAD" >&2
  exit 7
fi
if [[ "$FINAL_TREE" != "$TREE" ]]; then
  echo "PERF2.3 TREE moved during gate: $FINAL_TREE != $TREE" >&2
  exit 8
fi

TRACKED="$(git status --porcelain --untracked-files=no)"
if [[ -n "$TRACKED" ]]; then
  echo "PERF2.3 tracked worktree changed during gate" >&2
  printf '%s\n' "$TRACKED" >&2
  exit 9
fi

echo "PERF2.3 final HEAD=$FINAL_HEAD"
echo "PERF2.3 final TREE=$FINAL_TREE"
echo "PERF2.3 tracked worktree clean=YES"
echo "ECO.EVO7 PERF2.3 transitive simulation-scaling R1 acceptance: PASS"
