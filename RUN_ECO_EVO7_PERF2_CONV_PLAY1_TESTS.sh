#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

GODOT_BIN="${GODOT_BIN:-${GODOT_DOUBLE_BIN:-godot}}"
EXPECTED_GODOT="4.7.1.stable.double.custom_build.a13da4feb"
PERF2_RUNTIME_HEAD="81a0b3fa60664684b02d8387e4693c5f328dbe28"
PERF2_RUNTIME_TREE="a192950483267dd428baf2d1daa25de915df2370"
PERF2_CONTROL_HEAD="b4f73a4073ac16b2a1de535acd64ae16641d4588"
PERF2_REPORT_HASH="1064567c83c1bd023589fdf9e36f8436b9624eeb928e8b7d413b92ce3254c3f6"
VIS55_EXEC_HEAD="fb1a7ac21037e02033eae6d7e778ed8757514e19"
VIS55_EXEC_TREE="89551693f0cbac555a5026424d36b50cd35b8804"
VIS55_CLOSURE_HEAD="a73cccb8064fdfb4df266338d3d20e24ac9f082b"
VIS55_HANDOFF_HASH="bc6cc2f5a2301e0832d8ddb53a8145ce83dc83fb0d2313fe1b3cc1e5d49a5df9"

ACTUAL_GODOT="$("$GODOT_BIN" --version | head -n 1 | tr -d '\r')"
if [[ "$ACTUAL_GODOT" != "$EXPECTED_GODOT" ]]; then
  echo "PLAY1 BLOCKED: expected Godot '$EXPECTED_GODOT', got '$ACTUAL_GODOT'" >&2
  exit 2
fi

export GODOT_BIN
export GODOT_DOUBLE_BIN="$GODOT_BIN"
export BREAKPOINT_RUNTIME_DISABLED=1

LOCAL_HEAD="$(git rev-parse HEAD)"
LOCAL_TREE="$(git rev-parse 'HEAD^{tree}')"
TARGET_HEAD="${ECO_PLAY1_TARGET_HEAD:-$LOCAL_HEAD}"
TARGET_TREE="${ECO_PLAY1_TARGET_TREE:-$LOCAL_TREE}"

if [[ "$TARGET_HEAD" != "$LOCAL_HEAD" || "$TARGET_TREE" != "$LOCAL_TREE" ]]; then
  echo "PLAY1 BLOCKED: target identity differs from local exact subject" >&2
  exit 3
fi
if [[ ! "$TARGET_HEAD" =~ ^[0-9a-f]{40}$ || ! "$TARGET_TREE" =~ ^[0-9a-f]{40}$ ]]; then
  echo "PLAY1 BLOCKED: invalid target HEAD/TREE" >&2
  exit 3
fi

for sha in "$PERF2_RUNTIME_HEAD" "$PERF2_CONTROL_HEAD" "$VIS55_EXEC_HEAD" "$VIS55_CLOSURE_HEAD"; do
  git cat-file -e "$sha^{commit}" 2>/dev/null || { echo "PLAY1 BLOCKED: missing prerequisite $sha" >&2; exit 4; }
  git merge-base --is-ancestor "$sha" "$TARGET_HEAD" || { echo "PLAY1 BLOCKED: prerequisite is not ancestor: $sha" >&2; exit 4; }
done

[[ "$(git rev-parse "$PERF2_RUNTIME_HEAD^{tree}")" == "$PERF2_RUNTIME_TREE" ]] || { echo "PLAY1 BLOCKED: PERF2.CONV runtime tree mismatch" >&2; exit 4; }
[[ "$(git rev-parse "$VIS55_EXEC_HEAD^{tree}")" == "$VIS55_EXEC_TREE" ]] || { echo "PLAY1 BLOCKED: VIS5.5 executable tree mismatch" >&2; exit 4; }

grep -Fq "$PERF2_RUNTIME_HEAD" docs/checkpoints/2026-09-04_ECO_EVO7_PERF2_CONV_R3_ACCEPTED_RU.md
grep -Fq "$PERF2_CONTROL_HEAD" docs/checkpoints/2026-09-04_ECO_EVO7_PERF2_CONV_R3_ACCEPTED_RU.md
grep -Fq "$PERF2_REPORT_HASH" docs/checkpoints/2026-09-04_ECO_EVO7_PERF2_CONV_R3_ACCEPTED_RU.md
grep -Fq "$VIS55_EXEC_HEAD" docs/checkpoints/2026-09-04_ECO_EVO7_VIS5_5_VISUAL_EVIDENCE_INTEGRATED_PLAY1_HANDOFF_EXACT_VERIFIED_CLOSED_R1_RU.md
grep -Fq "$VIS55_HANDOFF_HASH" docs/checkpoints/2026-09-04_ECO_EVO7_VIS5_5_VISUAL_EVIDENCE_INTEGRATED_PLAY1_HANDOFF_EXACT_VERIFIED_CLOSED_R1_RU.md

echo "PLAY1 exact HEAD=$TARGET_HEAD"
echo "PLAY1 exact TREE=$TARGET_TREE"
echo "PLAY1 Godot=$ACTUAL_GODOT"
echo "PLAY1 accepted PERF2.CONV=$PERF2_RUNTIME_HEAD control=$PERF2_CONTROL_HEAD report=$PERF2_REPORT_HASH"
echo "PLAY1 exact-closed VIS5.5=$VIS55_EXEC_HEAD closure=$VIS55_CLOSURE_HEAD handoff=$VIS55_HANDOFF_HASH"
echo "PLAY1 prerequisite policy=NO_RERUN_ACCEPTED_PERF2_TIMING_CAMPAIGN"

if [[ ! -f "$ROOT/.godot/uid_cache.bin" ]]; then
  "$GODOT_BIN" --headless --editor --path "$ROOT" --import
fi

export ECO_PLAY1_TARGET_HEAD="$TARGET_HEAD"
export ECO_PLAY1_TARGET_TREE="$TARGET_TREE"
SAMPLE_DIR="$ROOT/artifacts/perf2/play1-integrated-run"
rm -rf "$SAMPLE_DIR"
mkdir -p "$SAMPLE_DIR"
export ECO_PLAY1_SAMPLE_DIR="$SAMPLE_DIR"

for repetition in 0 1 2; do
  echo "PLAY1 fresh repetition $repetition/2"
  ECO_PLAY1_REPETITION="$repetition" \
  ECO_PLAY1_SAMPLE_PATH="$SAMPLE_DIR/sample-$repetition.json" \
    "$GODOT_BIN" --headless --path "$ROOT" --script res://tests/ecology/eco_evo7_perf2_conv_play1_worker.gd
  test -s "$SAMPLE_DIR/sample-$repetition.json"
done

"$GODOT_BIN" --headless --path "$ROOT" --script res://tests/ecology/eco_evo7_perf2_conv_play1_aggregate_acceptance.gd

FINAL_HEAD="$(git rev-parse HEAD)"
FINAL_TREE="$(git rev-parse 'HEAD^{tree}')"
[[ "$FINAL_HEAD" == "$TARGET_HEAD" && "$FINAL_TREE" == "$TARGET_TREE" ]] || { echo "PLAY1 BLOCKED: subject moved during gate" >&2; exit 5; }
if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
  echo "PLAY1 BLOCKED: tracked worktree changed during gate" >&2
  git status --short
  exit 5
fi

echo "PLAY1 final HEAD=$FINAL_HEAD"
echo "PLAY1 final TREE=$FINAL_TREE"
echo "PLAY1 tracked worktree clean=YES"
echo "ECO.EVO7 PERF2.CONV / PLAY1 integrated candidate: PASS"
