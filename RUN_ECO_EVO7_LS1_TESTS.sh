#!/usr/bin/env bash
set -euo pipefail
GODOT_BIN="${GODOT_BIN:-${GODOT_DOUBLE_BIN:-godot}}"
EXPECTED="4.7.1.stable.double.custom_build.a13da4feb"
ACTUAL="$($GODOT_BIN --version | head -n 1 | tr -d '\r')"
if [[ "$ACTUAL" != "$EXPECTED" ]]; then
  echo "ECO.EVO7 LS1 BLOCKED: expected Godot '$EXPECTED', got '$ACTUAL'" >&2
  exit 2
fi
./RUN_ECO_EVO7_LIVE_SHADOW_TESTS.sh
"$GODOT_BIN" --headless --path . --script res://tests/ecology/eco_evo7_ls1_live_shadow_session_acceptance.gd
