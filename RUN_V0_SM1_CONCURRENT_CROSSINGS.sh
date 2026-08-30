#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-${GODOT:-}}"
EXPECTED_GODOT_VERSION="4.7.1.stable.double.custom_build.a13da4feb"
ITERATIONS="${SM1_CONCURRENT_ITERATIONS:-10}"

if [[ -z "$GODOT_BIN" ]]; then
  for candidate in godot4 godot; do
    if command -v "$candidate" >/dev/null 2>&1; then
      GODOT_BIN="$(command -v "$candidate")"
      break
    fi
  done
fi
if [[ -z "$GODOT_BIN" || ! -x "$GODOT_BIN" ]]; then
  echo "SM1_7_7_GODOT_NOT_FOUND: set GODOT_BIN to the Godot 4.7.1 double editor" >&2
  exit 2
fi
ACTUAL_GODOT_VERSION="$("$GODOT_BIN" --version | head -n 1 | tr -d '\r')"
if [[ "$ACTUAL_GODOT_VERSION" != "$EXPECTED_GODOT_VERSION" ]]; then
  echo "SM1_7_7_GODOT_VERSION_MISMATCH: expected=$EXPECTED_GODOT_VERSION actual=$ACTUAL_GODOT_VERSION" >&2
  exit 3
fi
TESTED_HEAD="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || true)"
if [[ -z "$TESTED_HEAD" ]]; then
  echo "SM1_7_7_GIT_HEAD_UNAVAILABLE" >&2
  exit 4
fi
if [[ -n "$(git -C "$ROOT" status --porcelain --untracked-files=all)" ]]; then
  echo "SM1_7_7_CHECKOUT_NOT_CLEAN" >&2
  git -C "$ROOT" status --short >&2
  exit 5
fi
if ! [[ "$ITERATIONS" =~ ^[0-9]+$ ]] || (( ITERATIONS < 1 )); then
  echo "SM1_7_7_ITERATIONS_INVALID: $ITERATIONS" >&2
  exit 6
fi

echo "SM1_7_7_GODOT_VERSION=$ACTUAL_GODOT_VERSION"
echo "SM1_7_7_TESTED_HEAD=$TESTED_HEAD"
echo "SM1_7_7_ITERATIONS=$ITERATIONS"

for ((i=1; i<=ITERATIONS; i++)); do
  echo "SM1_7_7_ITERATION=$i/$ITERATIONS"
  "$GODOT_BIN" --headless --path "$ROOT" --script res://tests/runtime/test_v0_sm1_concurrent_crossings.gd
  if [[ -n "$(git -C "$ROOT" status --porcelain --untracked-files=all)" ]]; then
    echo "SM1_7_7_CHECKOUT_DIRTY_AFTER_ITERATION=$i" >&2
    git -C "$ROOT" status --short >&2
    exit 7
  fi
done

echo "SM1_7_7_CONCURRENT_CROSSINGS_PASS"
echo "iterations=$ITERATIONS"
echo "head=$TESTED_HEAD"
echo "godot=$ACTUAL_GODOT_VERSION"
