#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-${1:-}}"
if [[ -z "$GODOT_BIN" ]]; then
  for candidate in godot4 godot; do
    if command -v "$candidate" >/dev/null 2>&1; then GODOT_BIN="$(command -v "$candidate")"; break; fi
  done
fi
[[ -n "$GODOT_BIN" && -x "$GODOT_BIN" ]] || { echo "Double-precision Godot was not found." >&2; exit 2; }
REPORT_ROOT="$PROJECT_ROOT/artifacts/test-results"
mkdir -p "$REPORT_ROOT"
run_checked() {
  local name="$1"; shift
  local log="$REPORT_ROOT/b0-${name}.log"
  set +e
  "$GODOT_BIN" "$@" 2>&1 | tee "$log"
  local exit_code=${PIPESTATUS[0]}
  set -e
  if [[ $exit_code -ne 0 ]] || grep -Eq ': FAIL([[:space:]]|\()' "$log"; then
    echo "$name failed (exit code $exit_code)" >&2
    exit 1
  fi
}
run_checked editor_import --headless --editor --path "$PROJECT_ROOT" --quit
run_checked contracts --headless --path "$PROJECT_ROOT" --script res://tests/network/test_b0_message_bus_contracts.gd
run_checked integration --headless --path "$PROJECT_ROOT" --script res://tests/network/test_b0_message_bus_integration.gd
echo "B0 message bus tests: PASS"
