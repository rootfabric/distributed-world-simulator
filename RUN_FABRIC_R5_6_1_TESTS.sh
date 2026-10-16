#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
: "${GODOT_BIN:?Set GODOT_BIN to canonical Linux Godot double}"
: "${R56_EXPECTED_HEAD:?Set R56_EXPECTED_HEAD}"
: "${R56_EXPECTED_TREE:?Set R56_EXPECTED_TREE}"
OUT="${R56_EVIDENCE_DIR:-$ROOT/artifacts/r56-$(date -u +%Y%m%dT%H%M%S)-$$}"
mkdir -p "$OUT"
test -z "$(find "$OUT" -mindepth 1 -maxdepth 1 -print -quit)" || { echo 'EVIDENCE_NOT_EMPTY' >&2; exit 1; }
export GODOT_SILENCE_ROOT_WARNING=1 BREAKPOINT_RUNTIME_DISABLED=1
engine_sha=bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
identity() {
  test -z "$(git status --porcelain=v1 --untracked-files=no)"
  test "$(git rev-parse HEAD)" = "$R56_EXPECTED_HEAD"
  test "$(git rev-parse 'HEAD^{tree}')" = "$R56_EXPECTED_TREE"
  test "$(sha256sum "$GODOT_BIN" | cut -d' ' -f1)" = "$engine_sha"
  test "$("$GODOT_BIN" --version | head -1 | tr -d '\r')" = '4.7.1.stable.double.custom_build.a13da4feb'
  printf 'HEAD=%s\nTREE=%s\nGODOT_VERSION=%s\nGODOT_SHA256=%s\n' "$R56_EXPECTED_HEAD" "$R56_EXPECTED_TREE" '4.7.1.stable.double.custom_build.a13da4feb' "$engine_sha"
}
run() {
  local name="$1";shift
  if [[ "$name" == "bridge4-regression" ]]; then
    timeout --kill-after=3s 45s "$GODOT_BIN" --headless --quit-after 2 --path "$ROOT" "$@" > "$OUT/$name.log" 2>&1
  else
    timeout --kill-after=5s 600s "$GODOT_BIN" --headless --path "$ROOT" "$@" > "$OUT/$name.log" 2>&1
  fi
  if grep -Eiq 'SCRIPT ERROR|Parse Error|Compile Error|Invalid call|Invalid access|ERROR:' "$OUT/$name.log";then echo "GODOT_FAILURE:$name" >&2;return 1;fi
  printf '%s=PASS\n' "$name"
}
identity > "$OUT/identity-before.txt"
rm -rf .godot
run import --editor --import
run parse --check-only --script res://tests/research/fabric_bake0/fabric_r5_6_1_canonical_delta_acceptance.gd
for i in 1 2 3; do run "sample-$i" --script res://tests/research/fabric_bake0/fabric_r5_6_1_canonical_delta_acceptance.gd; done
run bridge4-regression --script res://tests/research/fabric1/fabric_bridge4_canonical_world_acceptance.gd
identity > "$OUT/identity-after.txt"
python3 scripts/research/fabric_bake0/collect_r5_6_1_evidence.py --root "$OUT" --expected-head "$R56_EXPECTED_HEAD" --expected-tree "$R56_EXPECTED_TREE"
(cd "$OUT" && sha256sum -- *.log identity-before.txt identity-after.txt evidence.json > SHA256SUMS)
printf 'R5_6_1_EXACT=PASS\nEVIDENCE_DIR=%s\n' "$OUT"
