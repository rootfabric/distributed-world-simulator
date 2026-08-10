#!/usr/bin/env bash
set -euo pipefail
GODOT_PATH="${GODOT_BIN:-${1:-godot}}"
PROFILE="${2:-CUBE_10K}"
MODE="${3:-FAR}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$GODOT_PATH" --path "$PROJECT_ROOT" res://scenes/labs/construction/ts0_large_structural_visual_lab.tscn -- "--ts0-profile=$PROFILE" "--ts0-mode=$MODE"
