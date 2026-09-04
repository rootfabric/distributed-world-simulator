#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
GODOT_BIN="${GODOT_BIN:-${GODOT_DOUBLE_BIN:-godot}}"
exec "$GODOT_BIN" --editor --path "$ROOT" res://scenes/labs/ecology/eco_evo7_vis5_3_mixed_strata_composition_lab.tscn
