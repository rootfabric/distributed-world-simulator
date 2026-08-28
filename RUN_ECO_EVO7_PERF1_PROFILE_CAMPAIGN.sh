#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
GODOT_BIN="${GODOT_BIN:-${GODOT_DOUBLE_BIN:-godot}}"
EXPECTED="4.7.1.stable.double.custom_build.a13da4feb"
ACTUAL="$($GODOT_BIN --version | head -n 1 | tr -d '\r')"
if [[ "$ACTUAL" != "$EXPECTED" ]]; then
  echo "ECO.EVO7 PERF1 BLOCKED: expected Godot '$EXPECTED', got '$ACTUAL'" >&2
  exit 2
fi
export ECO_PERF1_GENERATIONS="${ECO_PERF1_GENERATIONS:-12}"
exec "$GODOT_BIN" --headless --path "$ROOT" --script res://scripts/ecology/perf/eco_evo7_perf1_profile_campaign_v1.gd
