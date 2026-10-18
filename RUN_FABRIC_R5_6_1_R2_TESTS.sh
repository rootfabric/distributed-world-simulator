#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
: "${GODOT_BIN:?Set GODOT_BIN to canonical Linux Godot 4.7.1 double}"
: "${R56_R2_EXPECTED_HEAD:?Set frozen PRODUCT_HEAD}"
: "${R56_R2_EXPECTED_TREE:?Set frozen PRODUCT_TREE}"
OUT="${R56_R2_EVIDENCE_DIR:-$ROOT/artifacts/r56-r2-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
mkdir -p "$OUT"
test -z "$(find "$OUT" -mindepth 1 -maxdepth 1 -print -quit)" || { echo EVIDENCE_DIRECTORY_NOT_EMPTY >&2; exit 1; }
export GODOT_SILENCE_ROOT_WARNING=1 BREAKPOINT_RUNTIME_DISABLED=1
ENGINE_SHA256=bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
identity(){
    test -z "$(git status --porcelain=v1 --untracked-files=no)"
    test "$(git rev-parse HEAD)" = "$R56_R2_EXPECTED_HEAD"
    test "$(git rev-parse 'HEAD^{tree}')" = "$R56_R2_EXPECTED_TREE"
    test "$(sha256sum "$GODOT_BIN" | cut -d' ' -f1)" = "$ENGINE_SHA256"
    test "$("$GODOT_BIN" --version | head -1 | tr -d '\r')" = '4.7.1.stable.double.custom_build.a13da4feb'
    printf 'HEAD=%s\nTREE=%s\nGODOT_VERSION=%s\nGODOT_SHA256=%s\n' "$R56_R2_EXPECTED_HEAD" "$R56_R2_EXPECTED_TREE" '4.7.1.stable.double.custom_build.a13da4feb' "$ENGINE_SHA256"
}
run(){
    local label="$1"; shift
    local prefix=(--headless --path "$ROOT")
    if [ "$label" = bridge4-regression ]; then prefix=(--headless --quit-after 2 --path "$ROOT");fi
    timeout --kill-after=5s 1800s "$GODOT_BIN" "${prefix[@]}" "$@" > "$OUT/$label.log" 2>&1
    if grep -Eiq 'SCRIPT ERROR|Parse Error|Compile Error|Invalid call|Invalid access|ERROR:' "$OUT/$label.log"; then echo "GODOT_ERROR:$label" >&2; exit 1;fi
    echo "$label=PASS"
}
identity > "$OUT/identity-before.txt"
rm -rf "$ROOT/.godot"
run import --editor --import
R=res://tests/research/fabric_bake0
run parse-r2 --check-only --script "$R/fabric_r5_6_1_r2_dynamic_aggregate_acceptance.gd"
run parse-scale --check-only --script "$R/fabric_r5_6_1_r2_dynamic_index_scale.gd"
run parse-numeric --check-only --script "$R/fabric_r5_6_1_r2_numeric_conditioning_acceptance.gd"
run parse-r1 --check-only --script "$R/fabric_r5_6_1_canonical_delta_acceptance.gd"
run parse-r1-narrow --check-only --script "$R/fabric_r5_6_1_r1_source_admission_acceptance.gd"
for i in 1 2 3; do run "r2-acceptance-$i" --script "$R/fabric_r5_6_1_r2_dynamic_aggregate_acceptance.gd";done
run r2-scale --script "$R/fabric_r5_6_1_r2_dynamic_index_scale.gd"
run r2-numeric --script "$R/fabric_r5_6_1_r2_numeric_conditioning_acceptance.gd"
run r1-acceptance --script "$R/fabric_r5_6_1_canonical_delta_acceptance.gd"
run r1-narrow-admission --script "$R/fabric_r5_6_1_r1_source_admission_acceptance.gd"
run bridge4-regression --script res://tests/research/fabric1/fabric_bridge4_canonical_world_acceptance.gd
identity > "$OUT/identity-after.txt"
python3 scripts/research/fabric_bake0/collect_r5_6_1_r2_evidence.py --root "$OUT" --expected-head "$R56_R2_EXPECTED_HEAD" --expected-tree "$R56_R2_EXPECTED_TREE"
python3 scripts/research/fabric_bake0/test_r5_6_1_r2_evidence_collector.py --root "$OUT"
(cd "$OUT" && sha256sum *.log identity-before.txt identity-after.txt evidence.json > SHA256SUMS)
echo 'FABRIC_R56_R2_EXACT=PASS'
echo "EVIDENCE_DIR=$OUT"
