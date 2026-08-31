#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

GODOT_BIN="${GODOT_BIN:-${GODOT_DOUBLE_BIN:-godot}}"
EXPECTED="4.7.1.stable.double.custom_build.a13da4feb"
ACTUAL="$("$GODOT_BIN" --version | head -n 1 | tr -d '\r')"

if [[ "$ACTUAL" != "$EXPECTED" ]]; then
  echo "ECO.EVO7 PERF2.CONV BLOCKED: expected Godot '$EXPECTED', got '$ACTUAL'" >&2
  exit 2
fi

export GODOT_BIN
export GODOT_DOUBLE_BIN="$GODOT_BIN"
export BREAKPOINT_RUNTIME_DISABLED=1

if [[ ! -f "$ROOT/.godot/uid_cache.bin" ]]; then
  "$GODOT_BIN" --headless --editor --path "$ROOT" --import
fi

LOCAL_HEAD="$(git rev-parse HEAD)"
LOCAL_TREE="$(git rev-parse HEAD^{tree})"
TARGET_HEAD="${ECO_PERF2_CONV_TARGET_HEAD:-$LOCAL_HEAD}"
TARGET_TREE="${ECO_PERF2_CONV_TARGET_TREE:-$LOCAL_TREE}"
if [[ "$TARGET_TREE" != "$LOCAL_TREE" ]]; then
  echo "PERF2.CONV BLOCKED: target TREE $TARGET_TREE != local TREE $LOCAL_TREE" >&2
  exit 3
fi
if [[ ! "$TARGET_HEAD" =~ ^[0-9a-f]{40}$ || ! "$TARGET_TREE" =~ ^[0-9a-f]{40}$ ]]; then
  echo "PERF2.CONV BLOCKED: invalid target HEAD/TREE identity" >&2
  exit 3
fi
export ECO_PERF2_CONV_TARGET_HEAD="$TARGET_HEAD"
export ECO_PERF2_CONV_TARGET_TREE="$TARGET_TREE"

echo "PERF2.CONV local HEAD=$LOCAL_HEAD"
echo "PERF2.CONV target HEAD=$TARGET_HEAD"
echo "PERF2.CONV target TREE=$TARGET_TREE"

echo "=== PERF2.4 prerequisite transitive gate ==="
bash ./RUN_ECO_EVO7_PERF2_4_TESTS.sh

echo "=== VIS4.9 prerequisite transitive gate ==="
bash ./RUN_ECO_EVO7_VIS4_9_TESTS.sh

echo "=== PERF2.CONV integrated STREAM1 + VIS4 gate ==="
"$GODOT_BIN" --headless --path "$ROOT"   --script res://tests/ecology/eco_evo7_perf2_conv_stream1_vis4_acceptance.gd

echo "ECO.EVO7 PERF2.CONV STREAM1 + VIS4 candidate: PASS"
