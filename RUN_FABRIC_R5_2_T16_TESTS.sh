#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
: "${GODOT_BIN:?Set GODOT_BIN to the canonical Linux double engine}"
EXPECTED=bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
OUT="${T16_EVIDENCE_DIR:-$ROOT/artifacts/fabric-r5-2-t16/$(date -u +%Y%m%dT%H%M%SZ)-$$}"
mkdir -p "$OUT"
test -z "$(find "$OUT" -mindepth 1 -maxdepth 1 -print -quit)" || { echo 'Evidence directory must be empty'; exit 1; }
export GODOT_SILENCE_ROOT_WARNING=1 BREAKPOINT_RUNTIME_DISABLED=1
identity() {
  test -z "$(git status --porcelain=v1 --untracked-files=no)"
  local sha version
  sha="$(sha256sum "$GODOT_BIN" | cut -d' ' -f1)"
  version="$("$GODOT_BIN" --version | head -n1 | tr -d '\r')"
  test "$sha" = "$EXPECTED"
  test "$version" = '4.7.1.stable.double.custom_build.a13da4feb'
  printf 'HEAD=%s\nTREE=%s\nGODOT_VERSION=%s\nGODOT_SHA256=%s\n' "$(git rev-parse HEAD)" "$(git rev-parse 'HEAD^{tree}')" "$version" "$sha"
}
identity > "$OUT/identity-before.txt"
rm -rf .godot
run() {
  local name="$1"; shift
  timeout --kill-after=5s 300s "$GODOT_BIN" --headless --path "$ROOT" "$@" > "$OUT/$name.log" 2>&1
  ! grep -Ei 'SCRIPT ERROR|Parse Error|Compile Error|Invalid call|Invalid access|ERROR:' "$OUT/$name.log"
}
run import --editor --import
SCRIPT=res://tests/research/fabric_bake0/fabric_r5_2_t16_no_safe_bake_acceptance.gd
run parse --check-only --script "$SCRIPT"
for i in 1 2 3; do run "sample-$i" --script "$SCRIPT"; done
run t15-regression --script res://tests/research/fabric_bake0/fabric_r5_2_t15_local_damage_acceptance.gd
run t14-regression --script res://tests/research/fabric_bake0/fabric_r5_2_t14_observation_refinement_acceptance.gd
run t13-5-regression --script res://tests/research/fabric_bake0/fabric_r5_2_t13_5_shared_families_acceptance.gd
run t13-regression --script res://tests/research/fabric_bake0/fabric_r5_2_t13_shared_instances_acceptance.gd
run t12-regression --script res://tests/research/fabric_bake0/fabric_r5_2_t12_ship_acceptance.gd
python3 -m unittest discover -s tests/research/fabric_bake0 -p test_t16_evidence.py -v > "$OUT/python-tests.log" 2>&1
identity > "$OUT/identity-after.txt"
python3 scripts/research/fabric_bake0/collect_r5_2_t16_evidence.py --root "$OUT"
printf 'EVIDENCE_DIR=%s\n' "$OUT"
