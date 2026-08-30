#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-${GODOT:-}}"
EXPECTED_GODOT_VERSION="4.7.1.stable.double.custom_build.a13da4feb"
ITERATIONS="${SM1_IMPAIRED_CROSSING_ITERATIONS:-5}"
if [[ -z "$GODOT_BIN" ]]; then
  for candidate in godot4 godot; do command -v "$candidate" >/dev/null 2>&1 && { GODOT_BIN="$(command -v "$candidate")"; break; }; done
fi
[[ -n "$GODOT_BIN" && -x "$GODOT_BIN" ]] || { echo "SM1_7_12_GODOT_NOT_FOUND" >&2; exit 2; }
ACTUAL_GODOT_VERSION="$($GODOT_BIN --version | head -n1 | tr -d '\r')"
[[ "$ACTUAL_GODOT_VERSION" == "$EXPECTED_GODOT_VERSION" ]] || { echo "SM1_7_12_GODOT_VERSION_MISMATCH expected=$EXPECTED_GODOT_VERSION actual=$ACTUAL_GODOT_VERSION" >&2; exit 3; }
TESTED_HEAD="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || true)"
[[ -n "$TESTED_HEAD" ]] || { echo "SM1_7_12_GIT_HEAD_UNAVAILABLE" >&2; exit 4; }
[[ -z "$(git -C "$ROOT" status --porcelain --untracked-files=all)" ]] || { echo "SM1_7_12_CHECKOUT_NOT_CLEAN" >&2; git -C "$ROOT" status --short >&2; exit 5; }
[[ "$ITERATIONS" =~ ^[0-9]+$ ]] && (( ITERATIONS >= 1 )) || { echo "SM1_7_12_ITERATIONS_INVALID: $ITERATIONS" >&2; exit 6; }
printf 'SM1_7_12_GODOT_VERSION=%s\nSM1_7_12_TESTED_HEAD=%s\nSM1_7_12_ITERATIONS=%s\n' "$ACTUAL_GODOT_VERSION" "$TESTED_HEAD" "$ITERATIONS"
for ((i=1; i<=ITERATIONS; i++)); do
  echo "SM1_7_12_ITERATION=$i/$ITERATIONS"
  GODOT_SILENCE_ROOT_WARNING=1 "$GODOT_BIN" --headless --path "$ROOT" --script res://tests/runtime/test_v0_sm1_repeated_crossings_impaired_network.gd
  [[ -z "$(git -C "$ROOT" status --porcelain --untracked-files=all)" ]] || { echo "SM1_7_12_CHECKOUT_DIRTY_AFTER_ITERATION=$i" >&2; exit 7; }
done
echo "SM1_7_12_REPEATED_CROSSINGS_IMPAIRED_NETWORK_PASS"
echo "iterations=$ITERATIONS"
echo "head=$TESTED_HEAD"
echo "godot=$ACTUAL_GODOT_VERSION"
