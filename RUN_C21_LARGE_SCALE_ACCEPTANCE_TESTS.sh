#!/usr/bin/env bash
set -euo pipefail
GODOT_PATH="${1:-godot}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$GODOT_PATH" --headless --editor --path "$PROJECT_ROOT" --quit
"$GODOT_PATH" --headless --path "$PROJECT_ROOT" --script res://tests/construction/test_c21_large_scale_acceptance_contracts.gd
"$GODOT_PATH" --headless --path "$PROJECT_ROOT" --script res://tests/construction/test_c21_large_scale_acceptance_integration.gd
"$GODOT_PATH" --headless --path "$PROJECT_ROOT" --script res://tests/construction/test_c21_large_scale_acceptance_soak.gd
