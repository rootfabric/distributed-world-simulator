#!/usr/bin/env bash
set -euo pipefail
GODOT_PATH="${1:-${GODOT_BIN:-godot}}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREVIOUS_BREAKPOINT_RUNTIME_DISABLED="${BREAKPOINT_RUNTIME_DISABLED-}"
export BREAKPOINT_RUNTIME_DISABLED=1
restore_breakpoint_runtime_disabled() {
  if [[ -n "$PREVIOUS_BREAKPOINT_RUNTIME_DISABLED" ]]; then
    export BREAKPOINT_RUNTIME_DISABLED="$PREVIOUS_BREAKPOINT_RUNTIME_DISABLED"
  else
    unset BREAKPOINT_RUNTIME_DISABLED
  fi
}
trap restore_breakpoint_runtime_disabled EXIT
"$GODOT_PATH" --headless --editor --path "$PROJECT_ROOT" --quit
"$GODOT_PATH" --headless --path "$PROJECT_ROOT" --script res://tests/construction/test_t1a0_complex_construct_demo_baseline.gd
"$GODOT_PATH" --headless --path "$PROJECT_ROOT" --script res://tests/construction/test_t1a1_part_visual_adapter.gd
echo "T1A.1 part visual adapter passed."
