#!/usr/bin/env bash
set -euo pipefail
GODOT_PATH="${1:-${GODOT_BIN:-godot}}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$GODOT_PATH" --headless --editor --path "$PROJECT_ROOT" --quit
for test in \
  res://tests/construction/ts0/ts0_fixture_contract_acceptance.gd \
  res://tests/construction/ts0/ts0_graphical_proxy_acceptance.gd \
  res://tests/construction/test_c22_compiled_proxy_graphical.gd \
  res://tests/construction/test_c24_proxy_mesh_backend_graphical.gd
do
  "$GODOT_PATH" --headless --path "$PROJECT_ROOT" --script "$test"
done
