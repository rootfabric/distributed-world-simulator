#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
: "${GODOT_BIN:?Set GODOT_BIN to canonical Linux double Godot}"
export GODOT_BIN GODOT="$GODOT_BIN" BREAKPOINT_RUNTIME_DISABLED=1

timeout --kill-after=5s 300s \
  "$GODOT_BIN" --headless --path "$ROOT" \
  --script res://tests/research/fabric_bake0/fabric_r5_2_t2_logic_acceptance.gd
