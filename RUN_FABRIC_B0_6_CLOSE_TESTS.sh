#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
: "${GODOT_BIN:?Set GODOT_BIN to the attached canonical double runtime}"
export BREAKPOINT_RUNTIME_DISABLED=1
out="${B06_LOG_DIR:-$(mktemp -d)}"
mkdir -p "$out"
export B06_LOG_DIR="$out"
: > "$out/timings.tsv"
suites=(
  RUN_FABRIC_B0_6_A_TESTS.sh
  RUN_FABRIC_B0_6_B_TESTS.sh
  RUN_FABRIC_B0_6_C_TESTS.sh
  RUN_FABRIC_B0_6_D_TESTS.sh
  RUN_FABRIC_B0_6_E_TESTS.sh
  RUN_FABRIC_BAKE_BRIDGE2_A_TESTS.sh
  RUN_FABRIC_BRIDGE2_CLOSURE_TESTS.sh
  RUN_FABRIC_COMPLEX1B_TESTS.sh
  RUN_FABRIC_COMPLEX2_TESTS.sh
  RUN_FABRIC_COMPLEX2B_TESTS.sh
  RUN_FABRIC_COMPLEX2C_TESTS.sh
  RUN_FABRIC_COMPLEX2D_TESTS.sh
  RUN_FABRIC_COMPLEX2E_TESTS.sh
  RUN_FABRIC_COMPLEX2_PERF_TESTS.sh
  RUN_FABRIC_COMPLEX2_CLOSE_TESTS.sh
  RUN_FABRIC_BAKE_B0_5_A_CLOSURE_TESTS.sh
  RUN_FABRIC_BAKE_B0_4_D_CLOSURE_TESTS.sh
  RUN_FABRIC_BAKE_B0_2_E_TESTS.sh
  RUN_FABRIC_BAKE_B0_2_D_TESTS.sh
  RUN_FABRIC_BAKE_B0_2_C_TESTS.sh
  RUN_FABRIC_BAKE_B0_2_AB_TESTS.sh
  RUN_FABRIC_BAKE_BRIDGE1_TESTS.sh
  RUN_FABRIC_BAKE_B0_1_TESTS.sh
  RUN_FABRIC_BAKE_B0_0_TESTS.sh
)
for runner in "${suites[@]}"; do
  echo "B06_CLOSURE_RUNNER=$runner"
  log="$out/${runner%.sh}.log"
  started="$(python3 -c 'import time; print(time.monotonic_ns())')"
  bash "$ROOT/$runner" 2>&1 | tee "$log"
  python3 - "$runner" "$started" >> "$out/timings.tsv" <<'PYTIME'
import sys, time
print(sys.argv[1] + "\t" + str((time.monotonic_ns() - int(sys.argv[2])) / 1e9))
PYTIME
  if grep -Eq 'SCRIPT ERROR|Parse Error|Invalid call|Assertion failed|^ERROR:|Segmentation fault' "$log"; then
    echo "B0.6 closure fatal runtime marker in $runner" >&2
    exit 5
  fi
  grep -q 'PASS' "$log" || { echo "No PASS in $runner" >&2; exit 6; }
done
python3 "$ROOT/scripts/research/fabric_bake0/validate_adaptive_closure.py" "$out" "${suites[@]}"
echo 'FABRIC B0.6 Adaptive Physical Fidelity: PASS'
