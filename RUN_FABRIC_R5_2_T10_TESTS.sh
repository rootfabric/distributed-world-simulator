#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
: "${GODOT_BIN:?Set GODOT_BIN to canonical Linux double Godot}"
export GODOT_BIN GODOT="$GODOT_BIN" BREAKPOINT_RUNTIME_DISABLED=1

preflight="$(mktemp)"
trap 'rm -f "$preflight"' EXIT
set +e
timeout --kill-after=3s 30s \
  "$GODOT_BIN" --headless --path "$ROOT" \
  --script res://tests/research/fabric_bake0/fabric_r5_2_t10_laser_cannon_acceptance.gd \
  -- --preflight >"$preflight" 2>&1
preflight_rc=$?
set -e
cat "$preflight"
test "$preflight_rc" -eq 0
grep -F 'FABRIC_R5_2_T10_PREFLIGHT=PASS' "$preflight"
if grep -Eiq 'SCRIPT ERROR|Parse Error|Compile Error|Invalid call|Invalid access|ERROR:' "$preflight"; then
  echo "R5.2 T10 preflight detected script/runtime error" >&2
  exit 1
fi

timeout --kill-after=5s 300s \
  "$GODOT_BIN" --headless --path "$ROOT" \
  --script res://tests/research/fabric_bake0/fabric_r5_2_t10_laser_cannon_acceptance.gd
