#!/usr/bin/env bash
set -euo pipefail
GODOT_PATH="${1:-godot}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$GODOT_PATH" --headless --editor --path "$PROJECT_ROOT" --quit
"$GODOT_PATH" --headless --path "$PROJECT_ROOT" --script res://tests/construction/test_c15_executable_utilities_contracts.gd
"$GODOT_PATH" --headless --path "$PROJECT_ROOT" --script res://tests/construction/test_c15_executable_utilities_integration.gd
