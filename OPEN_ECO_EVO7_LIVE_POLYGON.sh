#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
GODOT_BIN="${GODOT_BIN:-${GODOT_DOUBLE_BIN:-godot}}"
exec "$GODOT_BIN" --path "$ROOT" --resolution 1600x900 res://scenes/labs/ecology/eco_evo7_live_ecology_polygon.tscn
