#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

GODOT_BIN="${GODOT_BIN:-${GODOT_DOUBLE_BIN:-godot}}"
EXPECTED_GODOT="4.7.1.stable.double.custom_build.a13da4feb"
EXPECTED_BASE="4997f7116d0e4ac40ed88fe8a41a7b5029621d71"
EXPECTED_CONTRACT_BLOB="b076784f6b4016a0191e937c4e6ada1fe90c783b"
CONTRACT_PATH="config/ecology/eco-evo7-perf2-measurement-contract.v1.json"

ACTUAL_GODOT="$("$GODOT_BIN" --version | head -n 1 | tr -d '\r')"
if [[ "$ACTUAL_GODOT" != "$EXPECTED_GODOT" ]]; then
  echo "ECO.EVO7 PERF2.4 BLOCKED: expected Godot '$EXPECTED_GODOT', got '$ACTUAL_GODOT'" >&2
  exit 2
fi

HEAD="$(git rev-parse HEAD)"
TREE="$(git rev-parse 'HEAD^{tree}')"

if ! git merge-base --is-ancestor "$EXPECTED_BASE" "$HEAD"; then
  echo "PERF2.4 BASE MISMATCH: accepted PERF2.3 control tip is not an ancestor" >&2
  exit 3
fi

CONTRACT_BLOB="$(git rev-parse "HEAD:$CONTRACT_PATH")"
if [[ "$CONTRACT_BLOB" != "$EXPECTED_CONTRACT_BLOB" ]]; then
  echo "PERF2.4 CONTRACT DRIFT: expected $EXPECTED_CONTRACT_BLOB got $CONTRACT_BLOB" >&2
  exit 4
fi

# Runtime optimization is allowed only in the STREAM1 execution/profiling
# files below, the shared pure recruitment kernel used by both oracle and
# STREAM1, and the two canonical lineage mutation authority files. R5 adds the
# immutable EnvironmentSample cache seam. R8 adds only an optional prepared
# default-policy context through the SAME reproduce_bundle()/reproduce()
# implementations; mutation formulas/hashes remain frozen.
ALLOWED_RUNTIME_1="scripts/ecology/perf/eco_evo7_stream1_generation_stream_executor_v1.gd"
ALLOWED_RUNTIME_2="scripts/ecology/perf/eco_evo7_par3_candidate_kernel_v1.gd"
ALLOWED_RUNTIME_3="scripts/ecology/perf/eco_evo7_stream1_route_kernel_v1.gd"
ALLOWED_RUNTIME_4="scripts/ecology/perf/eco_evo7_perf24_runtime_optimization_profiler_v1.gd"
ALLOWED_RUNTIME_5="scripts/ecology/perf/eco_evo7_par0_recruitment_kernel_v1.gd"
ALLOWED_RUNTIME_6="scripts/research/ecology/plant_mutation_lineage_extension_evo7_v1.gd"
ALLOWED_RUNTIME_7="scripts/research/ecology/plant_mutation_lineage_kernel_v1.gd"

RUNTIME_DIFF="$(git diff --name-only "$EXPECTED_BASE...$HEAD" -- scripts/ecology scripts/research/ecology)"
if [[ -n "$RUNTIME_DIFF" ]]; then
  while IFS= read -r path; do
    case "$path" in
      "$ALLOWED_RUNTIME_1"|"$ALLOWED_RUNTIME_2"|"$ALLOWED_RUNTIME_3"|"$ALLOWED_RUNTIME_4"|"$ALLOWED_RUNTIME_5"|"$ALLOWED_RUNTIME_6"|"$ALLOWED_RUNTIME_7")
        ;;
      *)
        echo "PERF2.4 UNAUTHORIZED RUNTIME DIFF: $path" >&2
        exit 5
        ;;
    esac
  done <<< "$RUNTIME_DIFF"
fi

for required in "$ALLOWED_RUNTIME_1" "$ALLOWED_RUNTIME_2" "$ALLOWED_RUNTIME_3" "$ALLOWED_RUNTIME_4" "$ALLOWED_RUNTIME_5" "$ALLOWED_RUNTIME_6" "$ALLOWED_RUNTIME_7"; do
  if ! git diff --name-only "$EXPECTED_BASE...$HEAD" -- "$required" | grep -Fxq "$required"; then
    echo "PERF2.4 EXPECTED IMPLEMENTATION DIFF MISSING: $required" >&2
    exit 6
  fi
done

CPU_MODEL="$(lscpu | awk -F: '/Model name/ {sub(/^[ \t]+/,"",$2); print $2; exit}')"
HOST_DESCRIPTOR="$(printf '%s|%s|%s|%s' 'linux' "$(uname -srmo)" "$CPU_MODEL" "$(nproc)")"
HOST_FINGERPRINT="$(printf '%s' "$HOST_DESCRIPTOR" | sha256sum | awk '{print $1}')"

export ECO_PERF2_TARGET_HEAD="$HEAD"
export ECO_PERF2_TARGET_TREE="$TREE"
export ECO_PERF2_HOST_FINGERPRINT="$HOST_FINGERPRINT"
export BREAKPOINT_RUNTIME_DISABLED=1

echo "PERF2.4 exact target HEAD=$HEAD"
echo "PERF2.4 exact target TREE=$TREE"
echo "PERF2.4 accepted predecessor=$EXPECTED_BASE"
echo "PERF2.4 Godot=$ACTUAL_GODOT"
echo "PERF2.4 frozen contract blob=$CONTRACT_BLOB"
echo "PERF2.4 host fingerprint=$HOST_FINGERPRINT"
echo "PERF2.4 runtime allowlist=PASS"

LOG_ROOT="$ROOT/artifacts/perf24_gate_logs"
mkdir -p "$LOG_ROOT"

echo "PERF2.4 fresh import START"
"$GODOT_BIN" --headless --import --path "$ROOT" 2>&1 | tee "$LOG_ROOT/import.log"
echo "PERF2.4 fresh import PASS"

run_gate() {
  local name="$1"
  local script="$2"
  local stem="${name//./_}"
  echo "PERF2.4 GATE START $name"
  "$GODOT_BIN" --headless --path "$ROOT" \
    --log-file "$LOG_ROOT/${stem}.godot.log" \
    --script "$script" \
    2>&1 | tee "$LOG_ROOT/${stem}.console.log"
  echo "PERF2.4 GATE PASS $name"
}

run_gate "PERF1"   "res://tests/ecology/eco_evo7_perf1_generation_profiler_acceptance.gd"
run_gate "STREAM1" "res://tests/ecology/eco_evo7_stream1_generation_stream_acceptance.gd"
run_gate "PERF2.0" "res://tests/ecology/eco_evo7_perf2_measurement_contract_acceptance.gd"
run_gate "PERF2.1" "res://tests/ecology/eco_evo7_perf21_generation_profiling_acceptance.gd"
run_gate "PERF2.2" "res://tests/ecology/eco_evo7_perf22_working_set_memory_acceptance.gd"
run_gate "PERF2.3" "res://tests/ecology/eco_evo7_perf23_simulation_scaling_acceptance.gd"
run_gate "PERF2.4" "res://tests/ecology/eco_evo7_perf24_runtime_optimization_acceptance.gd"

REPORT="$ROOT/artifacts/perf2/perf2-4-runtime-optimization-r1.json"
if [[ ! -s "$REPORT" ]]; then
  echo "PERF2.4 report missing: $REPORT" >&2
  exit 7
fi

python3 - "$REPORT" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    r = json.load(f)

assert r["schema"] == "distributed_world_simulator.ecology.evo7_perf2_4.runtime_optimization_report.v1"
assert r["revision"] == "ECO.EVO7-PERF2.4-R1"
assert len(r["samples"]) == 54
assert len(r["comparisons"]) == 9

summary = r["optimization_summary"]
assert int(summary["exact_pairs"]) == 27
assert int(summary["comparison_points"]) == 9
assert summary["operation_reduction_proven"] is True
assert summary["bounded_working_set_preserved"] is True
assert float(summary["wall_geomean_speedup"]) >= 1.02
assert float(summary["stream_geomean_speedup"]) >= 1.03
assert int(summary["improved_wall_points"]) >= 6
assert int(summary["nonregressed_wall_points"]) == 9
assert summary["optimization_claim"] is True

claims = r["claims"]
assert claims["canonical_parity"] is True
assert claims["bounded_working_set_preserved"] is True
assert claims["deterministic_operation_reduction"] is True
assert claims["serial_crossover_claim"] is False
assert claims["optimization_claim"] is True

print("PERF2_4_SAMPLES=54")
print("PERF2_4_COMPARISONS=9")
print("PERF2_4_EXACT_AB_PAIRS=27/27")
print("PERF2_4_WALL_GEOMEAN_SPEEDUP=%.6f" % float(summary["wall_geomean_speedup"]))
print("PERF2_4_STREAM_GEOMEAN_SPEEDUP=%.6f" % float(summary["stream_geomean_speedup"]))
print("PERF2_4_IMPROVED_WALL_POINTS=%d/9" % int(summary["improved_wall_points"]))
print("PERF2_4_NONREGRESSED_WALL_POINTS=%d/9" % int(summary["nonregressed_wall_points"]))
print("PERF2_4_OPTIMIZATION_CLAIM=TRUE")
print("PERF2_4_REPORT_HASH=" + r["report_hash"])

for c in r["comparisons"]:
    print(
        "PERF2_4_PROFILE "
        f"scale={c['scale_id']} "
        f"chunk={int(c['stream_chunk_size'])} "
        f"wall_speedup={float(c['wall_speedup_legacy_over_optimized']):.6f} "
        f"stream_speedup={float(c['stream_speedup_legacy_over_optimized']):.6f} "
        f"context_reduction={float(c['context_build_reduction_factor']):.6f} "
        f"legacy_chunk_sorts={float(c['legacy_chunk_local_sorts_p50']):.0f} "
        f"optimized_chunk_sorts={float(c['optimized_chunk_local_sorts_p50']):.0f}"
    )
PY

FINAL_HEAD="$(git rev-parse HEAD)"
FINAL_TREE="$(git rev-parse 'HEAD^{tree}')"
if [[ "$FINAL_HEAD" != "$HEAD" ]]; then
  echo "PERF2.4 HEAD moved during gate: $FINAL_HEAD != $HEAD" >&2
  exit 8
fi
if [[ "$FINAL_TREE" != "$TREE" ]]; then
  echo "PERF2.4 TREE moved during gate: $FINAL_TREE != $TREE" >&2
  exit 9
fi

TRACKED="$(git status --porcelain --untracked-files=no)"
if [[ -n "$TRACKED" ]]; then
  echo "PERF2.4 tracked worktree changed during gate" >&2
  printf '%s\n' "$TRACKED" >&2
  exit 10
fi

echo "PERF2.4 final HEAD=$FINAL_HEAD"
echo "PERF2.4 final TREE=$FINAL_TREE"
echo "PERF2.4 tracked worktree clean=YES"
echo "ECO.EVO7 PERF2.4 transitive runtime-optimization R1 acceptance: PASS"
