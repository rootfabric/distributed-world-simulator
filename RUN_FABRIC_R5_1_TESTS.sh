#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
count="${1:?usage: RUN_FABRIC_R5_1_TESTS.sh COUNT}"
case "$count" in
  5000|20000|100000) ;;
  *) echo "unsupported R5.1 count: $count" >&2; exit 2 ;;
esac
: "${GODOT_BIN:?Set GODOT_BIN to canonical Linux double Godot}"
export GODOT_BIN GODOT="$GODOT_BIN" BREAKPOINT_RUNTIME_DISABLED=1

timeout --kill-after=5s 180s \
  "$GODOT_BIN" --headless --path "$ROOT" \
  --script res://tests/research/fabric_bake0/fabric_r5_1_quantitative_scale_acceptance.gd \
  -- --count="$count"
