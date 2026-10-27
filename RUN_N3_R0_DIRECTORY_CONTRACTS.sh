#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
GODOT_BIN="${1:-${GODOT_BIN:-godot}}"
for test_script in tests/network/test_n3_region_directory_contracts.gd tests/network/test_n3_directory_b0_routes.gd; do
    "$GODOT_BIN" --headless --path . --script "res://$test_script"
done
