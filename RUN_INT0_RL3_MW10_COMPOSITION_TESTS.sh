#!/usr/bin/env bash
set -euo pipefail

GODOT_PATH="${1:-${GODOT_BIN:-}}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "$GODOT_PATH" ]]; then
  echo "Godot path or GODOT_BIN is required." >&2
  exit 2
fi

"$GODOT_PATH" --headless --editor --path "$PROJECT_ROOT" --quit
"$GODOT_PATH" --headless --path "$PROJECT_ROOT" \
  --script res://tests/runtime/test_int0_project_uid_contracts.gd
"$GODOT_PATH" --headless --path "$PROJECT_ROOT" \
  --script res://tests/runtime/test_int0_m3_replica_resync_composition.gd

echo "INT0 RL3/MW10 composition focused gate: PASS"
