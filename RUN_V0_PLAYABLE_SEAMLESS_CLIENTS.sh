#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-${GODOT:-}}"
SCENARIO="${1:-all}"
OBSERVE="${DWS_TEST_CLIENT_OBSERVE:-1}"
STEP_MS="${DWS_TEST_CLIENT_STEP_MS:-800}"
EXPECTED="4.7.1.stable.double.custom_build.a13da4feb"

if [[ -z "$GODOT_BIN" || ! -x "$GODOT_BIN" ]]; then
  echo "Set GODOT_BIN to the Godot 4.7.1 double executable." >&2
  exit 2
fi

ACTUAL="$("$GODOT_BIN" --version | head -n 1 | tr -d '\r')"
if [[ "$ACTUAL" != "$EXPECTED" ]]; then
  echo "Godot version mismatch: expected=$EXPECTED actual=$ACTUAL" >&2
  exit 3
fi

export DWS_TEST_CLIENT_OBSERVE="$OBSERVE"
export DWS_TEST_CLIENT_STEP_MS="$STEP_MS"

run_gate() {
  local name="$1"
  local script="$2"
  echo
  echo "=== DWS TEST CLIENT: $name ==="
  "$GODOT_BIN" --headless --path "$ROOT" --script "$script"
}

run_gate "contracts" "res://tests/runtime/test_v0_test_client_contracts.gd"

case "${SCENARIO,,}" in
  seam)
    run_gate "seam" "res://tests/runtime/test_v0_test_client_seam_processes.gd"
    ;;
  items)
    run_gate "items" "res://tests/runtime/test_v0_test_client_items_processes.gd"
    ;;
  all)
    run_gate "seam" "res://tests/runtime/test_v0_test_client_seam_processes.gd"
    run_gate "items" "res://tests/runtime/test_v0_test_client_items_processes.gd"
    ;;
  *)
    echo "Scenario must be seam, items, or all" >&2
    exit 4
    ;;
esac

echo
echo "V0 PLAYABLE SEAMLESS TEST CLIENTS: PASS"
