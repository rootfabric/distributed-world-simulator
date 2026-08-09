#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_PATH="${GODOT_BIN:-${1:-}}"
if [[ -z "${GODOT_PATH}" ]]; then
  echo "GODOT_BIN or first argument is required." >&2
  exit 2
fi

export BREAKPOINT_RUNTIME_DISABLED=1

"${GODOT_PATH}" --headless --editor --path "${PROJECT_ROOT}" --quit
"${GODOT_PATH}" --headless --path "${PROJECT_ROOT}" --script res://tests/construction/test_t1a0_complex_construct_demo_baseline.gd
"${GODOT_PATH}" --headless --path "${PROJECT_ROOT}" --script res://tests/construction/test_t1a1_part_visual_adapter.gd
"${GODOT_PATH}" --headless --path "${PROJECT_ROOT}" --script res://tests/construction/test_c1_construct_aggregate.gd
"${GODOT_PATH}" --headless --path "${PROJECT_ROOT}" --script res://tests/construction/test_c2b_authoritative_item_graph_contracts.gd
"${GODOT_PATH}" --headless --path "${PROJECT_ROOT}" --script res://tests/construction/t1a2_d0_authoritative_outpost_builder_acceptance.gd

echo "T1A.2 D0 authoritative outpost builder focused gate passed."
