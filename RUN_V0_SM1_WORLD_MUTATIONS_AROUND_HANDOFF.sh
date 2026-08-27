#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-${GODOT:-}}"
EXPECTED_GODOT_VERSION="4.7.1.stable.double.custom_build.a13da4feb"
ITERATIONS="${SM1_WORLD_MUTATION_ITERATIONS:-10}"

if [[ -z "$GODOT_BIN" ]]; then
  for candidate in godot4 godot; do
    if command -v "$candidate" >/dev/null 2>&1; then GODOT_BIN="$(command -v "$candidate")"; break; fi
  done
fi
[[ -n "$GODOT_BIN" && -x "$GODOT_BIN" ]] || { echo "SM1_7_11_GODOT_NOT_FOUND" >&2; exit 2; }
ACTUAL_GODOT_VERSION="$("$GODOT_BIN" --version | head -n1 | tr -d '\r')"
[[ "$ACTUAL_GODOT_VERSION" == "$EXPECTED_GODOT_VERSION" ]] || { echo "SM1_7_11_GODOT_VERSION_MISMATCH expected=$EXPECTED_GODOT_VERSION actual=$ACTUAL_GODOT_VERSION" >&2; exit 3; }
TESTED_HEAD="$(git -C "$ROOT" rev-parse HEAD)"
[[ -z "$(git -C "$ROOT" status --porcelain --untracked-files=all)" ]] || { echo "SM1_7_11_CHECKOUT_NOT_CLEAN" >&2; git -C "$ROOT" status --short >&2; exit 4; }
[[ "$ITERATIONS" =~ ^[0-9]+$ ]] && (( ITERATIONS >= 1 )) || { echo "SM1_7_11_ITERATIONS_INVALID=$ITERATIONS" >&2; exit 5; }

echo "SM1_7_11_GODOT_VERSION=$ACTUAL_GODOT_VERSION"
echo "SM1_7_11_TESTED_HEAD=$TESTED_HEAD"
echo "SM1_7_11_ITERATIONS=$ITERATIONS"
for ((i=1; i<=ITERATIONS; i++)); do
  echo "SM1_7_11_ITERATION=$i/$ITERATIONS"
  GODOT_SILENCE_ROOT_WARNING=1 "$GODOT_BIN" --headless --path "$ROOT" --script res://tests/runtime/test_v0_sm1_world_mutations_around_handoff.gd
  [[ -z "$(git -C "$ROOT" status --porcelain --untracked-files=all)" ]] || { echo "SM1_7_11_CHECKOUT_DIRTY_AFTER_ITERATION=$i" >&2; exit 6; }
done

echo "SM1_7_11_WORLD_MUTATIONS_AROUND_HANDOFF_PASS"
echo "iterations=$ITERATIONS"
echo "head=$TESTED_HEAD"
echo "godot=$ACTUAL_GODOT_VERSION"
