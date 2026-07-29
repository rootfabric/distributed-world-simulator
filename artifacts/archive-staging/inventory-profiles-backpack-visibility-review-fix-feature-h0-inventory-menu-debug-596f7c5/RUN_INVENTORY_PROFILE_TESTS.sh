#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-${1:-}}"

if [[ -z "$GODOT_BIN" ]]; then
  for candidate in godot4 godot; do
    if command -v "$candidate" >/dev/null 2>&1; then
      GODOT_BIN="$(command -v "$candidate")"
      break
    fi
  done
fi

[[ -n "$GODOT_BIN" && -x "$GODOT_BIN" ]] || {
  echo "Double-precision Godot was not found. Set GODOT_BIN or pass the executable path." >&2
  exit 2
}

REPORT_ROOT="$PROJECT_ROOT/artifacts/test-results"
mkdir -p "$REPORT_ROOT"

run_checked() {
  local name="$1"
  shift
  local log="$REPORT_ROOT/inventory-profiles-${name}.log"
  set +e
  "$GODOT_BIN" "$@" 2>&1 | tee "$log"
  local exit_code=${PIPESTATUS[0]}
  set -e
  if [[ $exit_code -ne 0 ]] || grep -Eq ': FAIL([[:space:]]|\()' "$log"; then
    echo "$name failed (exit code $exit_code)" >&2
    exit 1
  fi
}

run_checked editor-import --headless --editor --path "$PROJECT_ROOT" --quit
run_checked profiles --headless --path "$PROJECT_ROOT" --script res://tests/ui/test_inventory_interaction_profiles.gd
run_checked stack-transfers --headless --path "$PROJECT_ROOT" --script res://tests/items/test_item_stack_transfers.gd
run_checked ui-i0 --headless --path "$PROJECT_ROOT" --script res://tests/ui/test_inventory_ui_i0_architecture.gd
run_checked ui-i1 --headless --path "$PROJECT_ROOT" --script res://tests/ui/test_inventory_ui_i1_interactions.gd
run_checked ui-i2 --headless --path "$PROJECT_ROOT" --script res://tests/ui/test_inventory_ui_i2_large_storage.gd

echo "Inventory interaction profile tests: PASS"
