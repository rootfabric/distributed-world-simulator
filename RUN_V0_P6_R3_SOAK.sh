#!/usr/bin/env bash
set -euo pipefail

# V0 P6 R3 literal thirty-minute two-client real-time soak runner (Ubuntu).
#
# Executes tests/runtime/test_v0_p6_thirty_minute_soak.gd with a generous
# timeout (45 min wall clock) and requires BOTH exit 0 AND the literal
# stage marker. No time acceleration is permitted anywhere in this path.
#
# Required: double-precision Godot 4.7.1 custom build a13da4feb.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-${1:-}}"
[[ -n "$GODOT_BIN" && -x "$GODOT_BIN" ]] || {
  echo "Double-precision Godot required (GODOT_BIN or \$1)" >&2
  exit 2
}

PROFILE="$ROOT/artifacts/test-results/p6-r3-soak-suite-$$"
mkdir -p "$PROFILE/data" "$PROFILE/config" "$PROFILE/cache"

TEST_SCRIPT="res://tests/runtime/test_v0_p6_thirty_minute_soak.gd"
LOG="$PROFILE/test_v0_p6_thirty_minute_soak.log"

set +e
GODOT_SILENCE_ROOT_WARNING=1 BREAKPOINT_RUNTIME_DISABLED=1 \
HOME="$PROFILE" APPDATA="$PROFILE/data" LOCALAPPDATA="$PROFILE/data" \
XDG_DATA_HOME="$PROFILE/data" XDG_CONFIG_HOME="$PROFILE/config" XDG_CACHE_HOME="$PROFILE/cache" \
timeout 2700s "$GODOT_BIN" --headless --path "$ROOT" --script "$TEST_SCRIPT" >"$LOG" 2>&1
EXIT_CODE=$?
set -e

STAGE="$(grep -oE '\[stage\] [A-Z0-9_]+' "$LOG" | tail -1 | sed 's/\[stage\] //' || true)"

if [[ $EXIT_CODE -eq 0 && "$STAGE" == "V0_P6_THIRTY_MINUTE_TWO_CLIENT_SOAK_PASS_REAL_TIME" ]] \
   && ! grep -Eq '(: FAIL([[:space:]]|\()|SCRIPT ERROR:|Parse Error:|Compile Error:)' "$LOG"; then
  echo "[p6-r3-soak-suite] PASS test_v0_p6_thirty_minute_soak -> $STAGE"
  echo "[p6-r3-soak-suite][stage] V0_P6_R3_SOAK_SUITE_PASS"
  echo "[p6-r3-soak-suite] log: $LOG"
  exit 0
fi

echo "[p6-r3-soak-suite] FAIL test_v0_p6_thirty_minute_soak (exit code $EXIT_CODE, stage: ${STAGE:-none})" >&2
tail -n 60 "$LOG" >&2
exit 1
