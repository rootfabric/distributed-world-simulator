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
  echo "SM1_6_GODOT_NOT_FOUND: set GODOT_BIN to the Godot 4.7.1 double editor" >&2
  exit 2
fi
ACTUAL_GODOT_VERSION="$("$GODOT_BIN" --version | head -n 1 | tr -d '\r')"
if [[ "$ACTUAL_GODOT_VERSION" != "$EXPECTED_GODOT_VERSION" ]]; then
  echo "SM1_6_GODOT_VERSION_MISMATCH: expected=$EXPECTED_GODOT_VERSION actual=$ACTUAL_GODOT_VERSION" >&2
  exit 3
fi
TESTED_HEAD="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || true)"
if [[ -z "$TESTED_HEAD" ]]; then
  echo "SM1_6_GIT_HEAD_UNAVAILABLE" >&2
  exit 4
fi
if [[ -n "$(git -C "$ROOT" status --porcelain --untracked-files=all)" ]]; then
  echo "SM1_6_CHECKOUT_NOT_CLEAN" >&2
  git -C "$ROOT" status --short >&2
  exit 5
fi
if [[ "$(uname -s)" == "Linux" && ! -x /usr/bin/Xvfb ]]; then
  echo "SM1_6_XVFB_REQUIRED" >&2
  exit 6
fi

echo "SM1_6_GODOT_VERSION=$ACTUAL_GODOT_VERSION"
echo "SM1_6_TESTED_HEAD=$TESTED_HEAD"

# Re-run the complete SM1.1-SM1.5 exact-head regression on the same checkout.
bash "$ROOT/RUN_V0_SM1_L0.sh"

"$GODOT_BIN" --headless --path "$ROOT" --script res://tests/runtime/test_v0_sm1_graphical_handoff_processes.gd

if [[ -n "$(git -C "$ROOT" status --porcelain --untracked-files=all)" ]]; then
  echo "SM1_6_CHECKOUT_DIRTY_AFTER_EXECUTION" >&2
  git -C "$ROOT" status --short >&2
  exit 7
fi

echo "SM1_6_GRAPHICAL_EXACT_HEAD_PASS head=$TESTED_HEAD godot=$ACTUAL_GODOT_VERSION"
