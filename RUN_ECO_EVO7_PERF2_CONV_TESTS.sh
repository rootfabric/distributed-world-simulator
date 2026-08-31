#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

GODOT_BIN="${GODOT_BIN:-${GODOT_DOUBLE_BIN:-godot}}"
EXPECTED_GODOT="4.7.1.stable.double.custom_build.a13da4feb"
PERF24_HEAD="8c022eaea2dd6253b3fd27a84d3db3e88c51d5a3"
PERF24_TREE="17635bb35101715205a960fdc41d16c179909101"
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

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dws-perf2-conv.XXXXXX")"
PERF24_DIR="$TMP_ROOT/perf24"
VIS49_DIR="$TMP_ROOT/vis49"

cleanup() {
  git worktree remove --force "$PERF24_DIR" >/dev/null 2>&1 || true
  git worktree remove --force "$VIS49_DIR" >/dev/null 2>&1 || true
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

echo "=== PERF2.4 exact prerequisite transitive gate ==="
git worktree add --detach "$PERF24_DIR" "$PERF24_HEAD"
(
  cd "$PERF24_DIR"
  test "$(git rev-parse HEAD)" = "$PERF24_HEAD"
  test "$(git rev-parse 'HEAD^{tree}')" = "$PERF24_TREE"
  export GODOT_BIN
  export GODOT_DOUBLE_BIN="$GODOT_BIN"
  export BREAKPOINT_RUNTIME_DISABLED=1
  bash ./RUN_ECO_EVO7_PERF2_4_TESTS.sh
)
echo "PERF2.CONV PERF2.4 exact prerequisite: PASS"

echo "=== VIS4.9 exact prerequisite transitive gate ==="
git worktree add --detach "$VIS49_DIR" "$VIS49_HEAD"
(
  cd "$VIS49_DIR"
  test "$(git rev-parse HEAD)" = "$VIS49_HEAD"
  test "$(git rev-parse 'HEAD^{tree}')" = "$VIS49_TREE"
  export GODOT_BIN
  export GODOT_DOUBLE_BIN="$GODOT_BIN"
  export BREAKPOINT_RUNTIME_DISABLED=1
  bash ./RUN_ECO_EVO7_VIS4_9_TESTS.sh
)
echo "PERF2.CONV VIS4.9 exact prerequisite: PASS"

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
