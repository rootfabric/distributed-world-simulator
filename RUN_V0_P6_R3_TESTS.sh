#!/usr/bin/env bash
set -euo pipefail

# V0 P6 R3 focused repair suite (Ubuntu).
#
# Runs the complete P6 test set against the R3 boundary:
# exactly-once admission, fail-closed ledger capacity, read-only projection,
# delegated authoritative persistence, shadow read-only fence and the
# rewritten legacy integration tests (composition level).
#
# Required: double-precision Godot 4.7.1 custom build a13da4feb.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-${1:-}}"
[[ -n "$GODOT_BIN" && -x "$GODOT_BIN" ]] || {
  echo "Double-precision Godot required (GODOT_BIN or \$1)" >&2
  exit 2
}

PROFILE="$ROOT/artifacts/test-results/p6-r3-focused-suite-$$"
mkdir -p "$PROFILE"

PASS_COUNT=0
FAIL_COUNT=0

run_test() {
  local name="$1"
  shift
  local home="$PROFILE/$name"
  local log="$PROFILE/$name.log"
  mkdir -p "$home/data" "$home/config" "$home/cache"

  set +e
  GODOT_SILENCE_ROOT_WARNING=1 BREAKPOINT_RUNTIME_DISABLED=1 \
  HOME="$home" APPDATA="$home/data" LOCALAPPDATA="$home/data" \
  XDG_DATA_HOME="$home/data" XDG_CONFIG_HOME="$home/config" XDG_CACHE_HOME="$home/cache" \
  timeout 300s "$GODOT_BIN" "$@" >"$log" 2>&1
  local exit_code=$?
  set -e

  local stage
  stage="$(grep -oE '\[stage\] [A-Z0-9_]+' "$log" | tail -1 | sed 's/\[stage\] //' || true)"
  if [[ -z "$stage" && "$name" == "editor-preflight" ]]; then
    stage="EDITOR_PREFLIGHT_OK"
  fi
  if (( exit_code == 0 )) && [[ -n "$stage" ]] && ! grep -Eq '(: FAIL([[:space:]]|\()|SCRIPT ERROR:|Parse Error:|Compile Error:)' "$log"; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo "[p6-r3-suite] PASS $name -> $stage"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "[p6-r3-suite] FAIL $name (exit code $exit_code, stage: ${stage:-none})" >&2
    tail -n 40 "$log" >&2
  fi
}

run_test editor-preflight --headless --editor --path "$ROOT" --quit

TESTS=(
  res://tests/runtime/test_v0_p6_identity_registry.gd
  res://tests/runtime/test_v0_p6_closure_adapter.gd
  res://tests/runtime/test_v0_p6_operation_ledger.gd
  res://tests/runtime/test_v0_p6_mutation_admission.gd
  res://tests/runtime/test_v0_p6_ownership_map.gd
  res://tests/runtime/test_v0_p6_persistence_owner.gd
  res://tests/runtime/test_v0_p6_outpost_state.gd
  res://tests/runtime/test_v0_p6_shadow_authority.gd
  res://tests/runtime/test_v0_p6_zero_write_fence.gd
  res://tests/runtime/test_v0_p6_gateway_command_route.gd
  res://tests/runtime/test_v0_p6_shared_outpost.gd
  res://tests/runtime/test_v0_p6_restart_recovery.gd
  res://tests/runtime/test_v0_p6_fault_race_matrix.gd
  res://tests/runtime/test_v0_p6_repeat_soak.gd
)

for test_script in "${TESTS[@]}"; do
  run_test "$(basename "$test_script" .gd)" --headless --path "$ROOT" --script "$test_script"
done

echo "[p6-r3-suite] passed: $PASS_COUNT failed: $FAIL_COUNT (logs: $PROFILE)"
(( FAIL_COUNT == 0 )) || exit 1

echo "[p6-r3-suite][stage] V0_P6_R3_FOCUSED_SUITE_PASS"
echo "[p6-r3-suite][scope] literal 30-minute two-client soak, MCP visual evidence and the OS-process M6-bound restart gate are NOT covered by this suite"
