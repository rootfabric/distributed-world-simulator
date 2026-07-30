#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
GODOT="${GODOT_BIN:-godot}"
"$GODOT" --headless --editor --path "$ROOT" --quit
"$GODOT" --headless --path "$ROOT" --script res://tests/runtime/test_h2_player_ownership_contracts.gd
"$GODOT" --headless --path "$ROOT" --script res://tests/runtime/test_h2_host_client_processes.gd
