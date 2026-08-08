#!/usr/bin/env bash
set -euo pipefail
GODOT_PATH="${1:-${GODOT_BIN:-godot}}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$GODOT_PATH" --headless --editor --path "$PROJECT_ROOT" --quit
"$GODOT_PATH" --headless --path "$PROJECT_ROOT" --script res://tests/construction/test_t1a0_complex_construct_demo_baseline.gd
echo "T1A.0 complex construct demo baseline passed."
