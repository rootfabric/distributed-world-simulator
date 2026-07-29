#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-${1:-}}"
[[ -n "$GODOT_BIN" && -x "$GODOT_BIN" ]] || { echo "Double-precision Godot was not found." >&2; exit 2; }
"$GODOT_BIN" --headless --editor --path "$ROOT" --quit
"$GODOT_BIN" --headless --path "$ROOT" --script res://tests/simulation/test_m0_aggregate_transaction_contracts.gd
"$GODOT_BIN" --headless --path "$ROOT" --script res://tests/simulation/test_m0_aggregate_transaction_integration.gd
echo "M0 aggregate transaction tests: PASS"
