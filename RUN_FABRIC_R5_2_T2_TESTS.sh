#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
: "${GODOT_BIN:?Set GODOT_BIN to canonical Linux double Godot}"
export GODOT_BIN GODOT="$GODOT_BIN" BREAKPOINT_RUNTIME_DISABLED=1

preflight="$(mktemp)"
trap 'rm -f "$preflight"' EXIT
timeout --kill-after=3s 30s   "$GODOT_BIN" --headless --path "$ROOT"   --script res://tests/research/fabric_bake0/fabric_r5_2_t2_logic_acceptance.gd   -- --preflight 2>&1 | tee "$preflight"
grep -F 'FABRIC_R5_2_T2_PREFLIGHT=PASS' "$preflight"
! grep -Eiq 'SCRIPT ERROR|Parse Error|Compile Error|Invalid call|Invalid access|ERROR:' "$preflight"

timeout --kill-after=5s 300s   "$GODOT_BIN" --headless --path "$ROOT"   --script res://tests/research/fabric_bake0/fabric_r5_2_t2_logic_acceptance.gd
