#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-${1:-}}"
[[ -n "$GODOT_BIN" && -x "$GODOT_BIN" ]] || { echo "Double-precision Godot was not found." >&2; exit 2; }
"$GODOT_BIN" --headless --editor --path "$ROOT" --quit
"$GODOT_BIN" --headless --path "$ROOT" --script res://tests/simulation/test_s1_distributed_compute_contracts.gd
"$GODOT_BIN" --headless --path "$ROOT" --script res://tests/simulation/test_s1_distributed_compute_integration.gd
echo "S1 distributed compute tests: PASS"
