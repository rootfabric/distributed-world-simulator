#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"
BASE=2c1802bf0b90c7ca11992cb1c166855f2d92c682
BASE_TREE=37494670a981cacb65761054e5d0953ffa0e719b
: "${GODOT_BIN:?Set the canonical Linux double executable}"
[[ -x "$GODOT_BIN" ]]
[[ "$("$GODOT_BIN" --version)" == '4.7.1.stable.double.custom_build.a13da4feb' ]]
[[ "$(sha256sum "$GODOT_BIN" | cut -d' ' -f1)" == bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7 ]]
[[ "$(git rev-parse "$BASE^{tree}")" == "$BASE_TREE" ]]
git merge-base --is-ancestor "$BASE" HEAD
[[ -z "$(git status --porcelain=v1 --untracked-files=no)" ]]
git diff --check
while IFS= read -r path; do
  case "$path" in
    scripts/research/fabric_bake0/fabric_composition_r3_*.gd|scripts/research/fabric_bake0/run_composition_r3_*.sh|tests/research/fabric1/fabric_composition_r3_*.gd|scenes/research/fabric_composition_r3_*.tscn|RUN_FABRIC_COMPOSITION_R3_TESTS.sh|.github/workflows/fabric-composition-r3-linux-double.yml|docs/research/FABRIC_COMPOSITION_R3_*.md|validation/fabric-composition-r3-*.json) ;;
    *) printf 'Out-of-scope path: %s\n' "$path" >&2; exit 9 ;;
  esac
done < <(git diff --name-only "$BASE" HEAD)
OUT="$ROOT/artifacts/fabric-composition-r3"
mkdir -p "$OUT"
export BREAKPOINT_RUNTIME_DISABLED=1 GODOT="$GODOT_BIN" R3_REPLAY_DIR="$OUT/replay"
printf '\n*.gd.uid\n' >> .git/info/exclude
printf 'HEAD=%s\nTREE=%s\nBASE=%s\nRUN=%s\nATTEMPT=%s\nRUNNER=%s\n' "$(git rev-parse HEAD)" "$(git rev-parse 'HEAD^{tree}')" "$BASE" "${GITHUB_RUN_ID:-local}" "${GITHUB_RUN_ATTEMPT:-1}" "${RUNNER_NAME:-local}" > "$OUT/subject.txt"
printf 'VERSION=%s\nSHA256=%s\n' "$("$GODOT_BIN" --version)" "$(sha256sum "$GODOT_BIN" | cut -d' ' -f1)" > "$OUT/godot.txt"
git diff --name-status "$BASE" HEAD > "$OUT/changed-paths.txt"
git archive --format=tar HEAD | gzip -9 > "$OUT/source.tar.gz"
git ls-files -z scripts/research/fabric0 scripts/research/fabric_bake0 scripts/construction scripts/simulation/matter scripts/network/contracts tests/research/fabric1 scenes/research | xargs -0 sha256sum > "$OUT/source-files.sha256"
: > "$OUT/exits.tsv"
run_gate() {
  local name="$1"
  shift
  printf '%s\t' "$name" >> "$OUT/commands.tsv"
  printf '%q ' "$@" >> "$OUT/commands.tsv"
  printf '\n' >> "$OUT/commands.tsv"
  set +e
  "$@" 2>&1 | tee "$OUT/$name.log"
  local statuses=("${PIPESTATUS[@]}")
  set -e
  printf '%s\t%s\t%s\n' "$name" "${statuses[0]}" "${statuses[1]}" >> "$OUT/exits.tsv"
  [[ "${statuses[0]}" == 0 && "${statuses[1]}" == 0 ]] || return 10
  if grep -Eiq 'SCRIPT ERROR|Parse Error|Invalid call|Invalid access|Assertion failed|ERROR:|Segmentation fault' "$OUT/$name.log"; then return 11; fi
}
: > "$OUT/commands.tsv"
rm -rf -- .godot
run_gate import timeout --kill-after=10s 180s "$GODOT_BIN" --headless --editor --path "$ROOT" --import
run_gate r3 timeout --kill-after=10s 300s bash RUN_FABRIC_COMPOSITION_R3_TESTS.sh
run_gate r2 timeout --kill-after=10s 300s bash RUN_FABRIC_PHYSICS_R2_TESTS.sh
run_gate r1 timeout --kill-after=10s 300s bash RUN_FABRIC_REPAIR_R1_TESTS.sh
# Headless observer integration above is mandatory. Rendering is supplemental:
# its absence is recorded, never promoted to a successful visual capture.
if command -v xvfb-run >/dev/null 2>&1; then
  run_gate render timeout --kill-after=10s 120s xvfb-run -a -s '-screen 0 1280x720x24' "$GODOT_BIN" --path "$ROOT" --rendering-method gl_compatibility --audio-driver Dummy --script res://tests/research/fabric1/fabric_composition_r3_render_capture.gd -- "$OUT/render"
  grep -Fq 'FABRIC-COMPOSITION-R3-RENDER: PASS' "$OUT/render.log"
else
  printf 'OPTIONAL_RENDER=NOT_RUN_NO_XVFB\n' > "$OUT/render-availability.txt"
fi
git diff --check
[[ -z "$(git status --porcelain=v1 --untracked-files=no)" ]]
printf 'IMPLEMENTER_EXACT_RESULT=PASS\nINDEPENDENT_REVIEW=PENDING\nINDEPENDENT_VERIFIER=PENDING\nMAIN_ACCEPTANCE=NOT_CLAIMED\n' > "$OUT/result.txt"
(cd "$OUT" && find . -type f ! -name evidence.sha256 -print0 | LC_ALL=C sort -z | xargs -0 sha256sum > evidence.sha256)
echo 'FABRIC-COMPOSITION-R3-EXACT: PASS'
