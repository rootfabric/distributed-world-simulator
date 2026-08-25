#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-${GODOT:-}}"
EXPECTED_GODOT_VERSION="4.7.1.stable.double.custom_build.a13da4feb"

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

ACTUAL_GODOT_VERSION="$("$GODOT_BIN" --version | head -n 1 | tr -d '\r')"
if [[ "$ACTUAL_GODOT_VERSION" != "$EXPECTED_GODOT_VERSION" ]]; then
  echo "SM1_L0_GODOT_VERSION_MISMATCH: expected=$EXPECTED_GODOT_VERSION actual=$ACTUAL_GODOT_VERSION" >&2
  exit 3
fi

TESTED_HEAD="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || true)"
if [[ -z "$TESTED_HEAD" ]]; then
  echo "SM1_L0_GIT_HEAD_UNAVAILABLE" >&2
  exit 4
fi

echo "SM1_L0_GODOT_VERSION=$ACTUAL_GODOT_VERSION"
echo "SM1_L0_TESTED_HEAD=$TESTED_HEAD"

"$GODOT_BIN" --headless --path "$ROOT" --script res://tests/runtime/test_v0_sm1_owner_map_and_transfer.gd
"$GODOT_BIN" --headless --path "$ROOT" --script res://tests/network/test_v0_sm1_player_carry_and_gateway_pivot.gd
"$GODOT_BIN" --headless --path "$ROOT" --script res://tests/runtime/test_v0_sm1_world_state_continuity.gd
"$GODOT_BIN" --headless --path "$ROOT" --script res://tests/runtime/test_v0_sm1_combined_carry_world_chain.gd

echo "SM1_L0_EXACT_HEAD_EXECUTABLE_PASS head=$TESTED_HEAD godot=$ACTUAL_GODOT_VERSION"
