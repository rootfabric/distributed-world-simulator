#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

GODOT_BIN="${GODOT_BIN:-${GODOT_DOUBLE_BIN:-godot}}"
EXPECTED_GODOT="4.7.1.stable.double.custom_build.a13da4feb"
PERF24_HEAD="840cfcea62ef7192b510235f915b849829654c6c"
PERF24_TREE="967d674c0ba2349db949193969f16f91553761ea"
PERF24_ACCEPTED_CONTROL_HEAD="ab115385e81375b224eb397cf6a9de071bd4e79e"
PERF24_REPORT_HASH="16d3407abef3d3ff30cbe4293cb1278e1b18845b0b5332589587d543b134853b"
PERF24_ACCEPTANCE_CHECKPOINT="docs/checkpoints/2026-09-04_ECO_EVO7_PERF2_4_R12_ACCEPTED_RU.md"
VIS49_HEAD="ab44617d8961add81a6c9f245c99d0b68eaeab52"
VIS49_TREE="9d543a3db4f54a676e9f25152785c36a72c56a30"

ACTUAL_GODOT="$("$GODOT_BIN" --version | head -n 1 | tr -d '\r')"
if [[ "$ACTUAL_GODOT" != "$EXPECTED_GODOT" ]]; then
  echo "ECO.EVO7 PERF2.CONV BLOCKED: expected Godot '$EXPECTED_GODOT', got '$ACTUAL_GODOT'" >&2
  exit 2
fi

export GODOT_BIN
export GODOT_DOUBLE_BIN="$GODOT_BIN"
export BREAKPOINT_RUNTIME_DISABLED=1

LOCAL_HEAD="$(git rev-parse HEAD)"
LOCAL_TREE="$(git rev-parse 'HEAD^{tree}')"
TARGET_HEAD="${ECO_PERF2_CONV_TARGET_HEAD:-$LOCAL_HEAD}"
TARGET_TREE="${ECO_PERF2_CONV_TARGET_TREE:-$LOCAL_TREE}"

if [[ "$TARGET_HEAD" != "$LOCAL_HEAD" ]]; then
  echo "PERF2.CONV BLOCKED: target HEAD $TARGET_HEAD != local HEAD $LOCAL_HEAD" >&2
  exit 3
fi
if [[ "$TARGET_TREE" != "$LOCAL_TREE" ]]; then
  echo "PERF2.CONV BLOCKED: target TREE $TARGET_TREE != local TREE $LOCAL_TREE" >&2
  exit 3
fi
if [[ ! "$TARGET_HEAD" =~ ^[0-9a-f]{40}$ || ! "$TARGET_TREE" =~ ^[0-9a-f]{40}$ ]]; then
  echo "PERF2.CONV BLOCKED: invalid target HEAD/TREE identity" >&2
  exit 3
fi

for pair in "$PERF24_HEAD:$PERF24_TREE" "$VIS49_HEAD:$VIS49_TREE"; do
  sha="${pair%%:*}"
  expected_tree="${pair#*:}"
  if ! git cat-file -e "$sha^{commit}" 2>/dev/null; then
    echo "PERF2.CONV BLOCKED: prerequisite commit missing: $sha" >&2
    exit 4
  fi
  actual_tree="$(git rev-parse "$sha^{tree}")"
  if [[ "$actual_tree" != "$expected_tree" ]]; then
    echo "PERF2.CONV BLOCKED: prerequisite TREE mismatch for $sha: $actual_tree != $expected_tree" >&2
    exit 4
  fi
done

export ECO_PERF2_CONV_TARGET_HEAD="$TARGET_HEAD"
export ECO_PERF2_CONV_TARGET_TREE="$TARGET_TREE"

echo "PERF2.CONV exact HEAD=$TARGET_HEAD"
echo "PERF2.CONV exact TREE=$TARGET_TREE"
echo "PERF2.CONV Godot=$ACTUAL_GODOT"
echo "PERF2.CONV PERF2.4 prerequisite=$PERF24_HEAD / $PERF24_TREE"
echo "PERF2.CONV VIS4.9 prerequisite=$VIS49_HEAD / $VIS49_TREE"

echo "=== immutable prerequisite provenance ==="
if ! git merge-base --is-ancestor "$PERF24_HEAD" "$TARGET_HEAD"; then
  echo "PERF2.CONV BLOCKED: accepted PERF2.4 runtime is not an ancestor" >&2
  exit 4
fi
if ! git merge-base --is-ancestor "$PERF24_ACCEPTED_CONTROL_HEAD" "$TARGET_HEAD"; then
  echo "PERF2.CONV BLOCKED: PERF2.4 acceptance control tip is not an ancestor" >&2
  exit 4
fi
if ! git merge-base --is-ancestor "$VIS49_HEAD" "$TARGET_HEAD"; then
  echo "PERF2.CONV BLOCKED: tested VIS4.9 prerequisite is not an ancestor" >&2
  exit 4
fi
ACCEPTANCE_PATH="$ROOT/$PERF24_ACCEPTANCE_CHECKPOINT"
if [[ ! -f "$ACCEPTANCE_PATH" ]]; then
  echo "PERF2.CONV BLOCKED: PERF2.4 acceptance checkpoint missing" >&2
  exit 4
fi
grep -Fq "$PERF24_HEAD" "$ACCEPTANCE_PATH"
grep -Fq "$PERF24_TREE" "$ACCEPTANCE_PATH"
grep -Fq "$PERF24_REPORT_HASH" "$ACCEPTANCE_PATH"
echo "PERF2.CONV PERF2.4 immutable accepted prerequisite: PASS"
echo "PERF2.CONV VIS4.9 immutable tested prerequisite: PASS"
echo "PERF2.CONV prerequisite rerun policy=NO_RERUN_ACCEPTED_IMMUTABLE_EVIDENCE"

if [[ ! -f "$ROOT/.godot/uid_cache.bin" ]]; then
  "$GODOT_BIN" --headless --editor --path "$ROOT" --import
fi

echo "=== PERF2.CONV integrated STREAM1 + VIS4 gate ==="
"$GODOT_BIN" --headless --path "$ROOT" \
  --script res://tests/ecology/eco_evo7_perf2_conv_stream1_vis4_acceptance.gd

FINAL_HEAD="$(git rev-parse HEAD)"
FINAL_TREE="$(git rev-parse 'HEAD^{tree}')"
if [[ "$FINAL_HEAD" != "$TARGET_HEAD" || "$FINAL_TREE" != "$TARGET_TREE" ]]; then
  echo "PERF2.CONV BLOCKED: subject moved during gate" >&2
  exit 5
fi
if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
  echo "PERF2.CONV BLOCKED: tracked worktree changed during gate" >&2
  git status --short
  exit 5
fi

echo "PERF2.CONV final HEAD=$FINAL_HEAD"
echo "PERF2.CONV final TREE=$FINAL_TREE"
echo "PERF2.CONV tracked worktree clean=YES"
echo "ECO.EVO7 PERF2.CONV STREAM1 + VIS4 candidate: PASS"
