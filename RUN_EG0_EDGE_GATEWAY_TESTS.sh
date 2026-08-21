#!/usr/bin/env bash
set -Eeuo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
godot_bin="${GODOT_BIN:-$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64}"

if [[ ! -x "$godot_bin" ]]; then
  if command -v godot4 >/dev/null 2>&1; then
    godot_bin="$(command -v godot4)"
  elif command -v godot >/dev/null 2>&1; then
    godot_bin="$(command -v godot)"
  else
    echo "Double-precision Godot not found. Set GODOT_BIN." >&2
    exit 2
  fi
fi

mkdir -p "$project_root/artifacts/test-results/eg0"

BREAKPOINT_RUNTIME_DISABLED=1 "$godot_bin" \
  --headless --editor --path "$project_root" --quit

for test_script in \
  res://tests/network/test_eg0_edge_gateway_contracts.gd \
  res://tests/network/test_eg0_edge_gateway_fixtures.gd \
  res://tests/network/test_eg0_world_graph_contracts.gd \
  res://tests/network/test_eg0_cwip_connect_gate_contracts.gd
do
  BREAKPOINT_RUNTIME_DISABLED=1 "$godot_bin" \
    --headless --path "$project_root" --script "$test_script"
done

echo "EG0 Edge Gateway focused suite: PASS"
