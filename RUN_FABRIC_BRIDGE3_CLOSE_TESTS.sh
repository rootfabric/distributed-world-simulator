#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
: "${GODOT_BIN:?Set GODOT_BIN to the attached canonical double runtime}"
out="${BRIDGE3_LOG_DIR:-$(mktemp -d)}"
mkdir -p "$out"
run() {
  local runner="$1"; shift || true
  echo "BRIDGE3_CLOSURE_RUNNER=$runner"
  bash "$ROOT/$runner" "$@" 2>&1 | tee "$out/${runner%.sh}.log"
  local p=("${PIPESTATUS[@]}")
  [[ "${p[0]}" == 0 && "${p[1]}" == 0 ]] || return 1
}
for runner in \
  RUN_FABRIC_BRIDGE3_A_TESTS.sh \
  RUN_FABRIC_BRIDGE3_B_TESTS.sh \
  RUN_FABRIC_BRIDGE3_C_TESTS.sh \
  RUN_FABRIC_BRIDGE3_D_TESTS.sh \
  RUN_FABRIC_BRIDGE3_E_TESTS.sh \
  RUN_FABRIC_BRIDGE3_F_TESTS.sh \
  RUN_FABRIC_BRIDGE3_G_TESTS.sh \
  RUN_FABRIC_B0_6_A_TESTS.sh \
  RUN_FABRIC_B0_6_B_TESTS.sh \
  RUN_FABRIC_B0_6_C_TESTS.sh \
  RUN_FABRIC_B0_6_D_TESTS.sh \
  RUN_FABRIC_B0_6_E_TESTS.sh \
  RUN_FABRIC_BRIDGE2_CLOSURE_TESTS.sh \
  RUN_FABRIC_COMPLEX2_CLOSE_TESTS.sh \
  RUN_FABRIC_COMPLEX2_PERF_TESTS.sh \
  RUN_FABRIC_BAKE_B0_5_A_CLOSURE_TESTS.sh
 do
  run "$runner"
 done
python3 "$ROOT/scripts/research/fabric_bake0/validate_bridge3_closure.py" "$out" | tee "$out/closure-validator.log"
echo 'FABRIC BRIDGE-3 FULL→BAKE→LOCAL_UNBAKE→FULL→REBAKE: PASS'
