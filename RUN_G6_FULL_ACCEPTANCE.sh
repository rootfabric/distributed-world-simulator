#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-}"
GLOBAL_CONFIG_PATH="config/architecture/global-program-roadmap.v1.json"
G5_REF="origin/feature/g5-world-feature-graph"
MAIN_REF="origin/main"
MW10_REPOSITORY_PATH="scripts/simulation/matter/transactions/distributed/matter_cross_region_transaction_repository.gd"
MW10_RETRY_TEST_PATH="tests/matter/transactions/test_mw10_lock_release_retry.gd"
EXPECTED_MW10_REPOSITORY_BLOB="a25b7d8c358410e60e1bb7db9d3f99333a305a63"
EXPECTED_MW10_RETRY_TEST_BLOB="afab0c98de45c34dcf6c923d622c84835d428fa5"

if [[ -z "$GODOT_BIN" || ! -x "$GODOT_BIN" ]]; then
  echo "GODOT_BIN must point to an executable Godot 4.7.1 double-precision editor" >&2
  exit 1
fi

printf '%s\n' '=== G6 FULL ACCEPTANCE: repository / sync preflight ==='
if [[ -n "$(git -C "$ROOT_DIR" status --porcelain)" ]]; then
  echo "G6 full acceptance requires a clean working tree" >&2
  exit 1
fi
for ref in "$MAIN_REF" "$G5_REF"; do
  git -C "$ROOT_DIR" rev-parse --verify --quiet "$ref" >/dev/null || {
    echo "Missing required ref $ref. Run git fetch origin first." >&2
    exit 1
  }
done

local_global_blob="$(git -C "$ROOT_DIR" hash-object "$ROOT_DIR/$GLOBAL_CONFIG_PATH")"
main_global_blob="$(git -C "$ROOT_DIR" rev-parse "$MAIN_REF:$GLOBAL_CONFIG_PATH")"
g5_global_blob="$(git -C "$ROOT_DIR" rev-parse "$G5_REF:$GLOBAL_CONFIG_PATH")"
[[ "$local_global_blob" == "$main_global_blob" ]] || { echo "G6 global config differs from main" >&2; exit 1; }
[[ "$local_global_blob" == "$g5_global_blob" ]] || { echo "G6 global config differs from G5" >&2; exit 1; }

git -C "$ROOT_DIR" merge-base --is-ancestor "$G5_REF" HEAD || {
  echo "Current G6 head is not synchronized on top of current G5" >&2
  exit 1
}

printf '%s\n' '=== G6 FULL ACCEPTANCE: shared MW10 baseline ==='
g5_repo_blob="$(git -C "$ROOT_DIR" rev-parse "$G5_REF:$MW10_REPOSITORY_PATH")"
g5_retry_blob="$(git -C "$ROOT_DIR" rev-parse "$G5_REF:$MW10_RETRY_TEST_PATH")"
[[ "$g5_repo_blob" == "$EXPECTED_MW10_REPOSITORY_BLOB" ]] || { echo "G5 lacks accepted MW10 atomic-lock repository blob" >&2; exit 1; }
[[ "$g5_retry_blob" == "$EXPECTED_MW10_RETRY_TEST_BLOB" ]] || { echo "G5 lacks accepted MW10 retry-test blob" >&2; exit 1; }
[[ "$(git -C "$ROOT_DIR" hash-object "$ROOT_DIR/$MW10_REPOSITORY_PATH")" == "$EXPECTED_MW10_REPOSITORY_BLOB" ]] || { echo "G6 is not resynchronized with MW10 repository fix" >&2; exit 1; }
[[ "$(git -C "$ROOT_DIR" hash-object "$ROOT_DIR/$MW10_RETRY_TEST_PATH")" == "$EXPECTED_MW10_RETRY_TEST_BLOB" ]] || { echo "G6 is not resynchronized with MW10 retry test" >&2; exit 1; }

git -C "$ROOT_DIR" diff --check "$G5_REF...HEAD"

grep -Fq '"decision": "ACCEPTED"' "$ROOT_DIR/validation/g6-4-casual-visual-river-lab-validation.json" || {
  echo "G6.4 acceptance record is missing or stale" >&2
  exit 1
}

previous_breakpoint_disabled="${BREAKPOINT_RUNTIME_DISABLED-__UNSET__}"
export BREAKPOINT_RUNTIME_DISABLED=1
trap 'if [[ "$previous_breakpoint_disabled" == "__UNSET__" ]]; then unset BREAKPOINT_RUNTIME_DISABLED; else export BREAKPOINT_RUNTIME_DISABLED="$previous_breakpoint_disabled"; fi' EXIT

printf '%s\n' '=== G6 FULL ACCEPTANCE: rerun accepted G6.0-G6.4 chain ==='
bash "$ROOT_DIR/RUN_G6_4_CASUAL_VISUAL_RIVER_LAB_TESTS.sh"

printf '%s\n' '=== G6 FULL ACCEPTANCE: MW10 atomic-lock fault injection ==='
"$GODOT_BIN" --headless --path "$ROOT_DIR" --script res://tests/matter/transactions/test_mw10_lock_release_retry.gd

printf '%s\n' '=== G6 FULL ACCEPTANCE: full world/core regression ==='
pwsh -NoProfile -File "$ROOT_DIR/RUN_WORLD_REGRESSION_TESTS.ps1"

printf '%s\n' '=== G6 FULL ACCEPTANCE: final hygiene ==='
[[ -z "$(git -C "$ROOT_DIR" status --porcelain)" ]] || { echo "G6 full acceptance left repository changes" >&2; exit 1; }
git -C "$ROOT_DIR" diff --check "$G5_REF...HEAD"

printf '%s\n' 'G6 FULL ACCEPTANCE: PASS'
