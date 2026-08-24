#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-${GODOT:-}}"

if [[ -z "$GODOT_BIN" ]]; then
  for candidate in godot4 godot; do
    if command -v "$candidate" >/dev/null 2>&1; then
      GODOT_BIN="$(command -v "$candidate")"
      break
    fi
  done
fi

if [[ -z "$GODOT_BIN" || ! -x "$GODOT_BIN" ]]; then
  echo "SM1_L0_GODOT_NOT_FOUND: set GODOT_BIN to the Godot 4.7.1 double editor" >&2
  exit 2
fi

"$GODOT_BIN" --headless --path "$ROOT" --script res://tests/runtime/test_v0_sm1_owner_map_and_transfer.gd
"$GODOT_BIN" --headless --path "$ROOT" --script res://tests/network/test_v0_sm1_player_carry_and_gateway_pivot.gd
