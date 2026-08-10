#!/usr/bin/env bash
set -euo pipefail
GODOT_PATH="${GODOT_BIN:-${1:-godot}}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$GODOT_PATH" --headless --editor --path "$PROJECT_ROOT" --quit
"$GODOT_PATH" --headless --path "$PROJECT_ROOT" --script res://tests/construction/ts0/ts0_local_dirty_rebuild_acceptance.gd
"$GODOT_PATH" --headless --path "$PROJECT_ROOT" --script res://tests/construction/test_c24_proxy_mesh_backend_contracts.gd
