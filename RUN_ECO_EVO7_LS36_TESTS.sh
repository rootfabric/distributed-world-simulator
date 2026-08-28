#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
GODOT_BIN="${GODOT_BIN:-${GODOT_DOUBLE_BIN:-godot}}"
EXPECTED="4.7.1.stable.double.custom_build.a13da4feb"
ACTUAL="$($GODOT_BIN --version | head -n 1 | tr -d '\r')"
if [[ "$ACTUAL" != "$EXPECTED" ]]; then
  echo "ECO.EVO7 LS3.6 BLOCKED: expected Godot '$EXPECTED', got '$ACTUAL'" >&2
  exit 2
fi
GODOT_BIN="$GODOT_BIN" ./RUN_ECO_EVO7_LS35_TESTS.sh
"$GODOT_BIN" --headless --path "$ROOT" --script res://tests/ecology/eco_evo7_ls36_rule_workbench_acceptance.gd
