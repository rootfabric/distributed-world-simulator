#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
: "${GODOT_BIN:?Set GODOT_BIN to canonical Linux Godot 4.7.1 double}"
: "${R562_R1_EXPECTED_HEAD:?Set frozen product head}"
: "${R562_R1_EXPECTED_TREE:?Set frozen product tree}"
OUT="${R562_R1_EVIDENCE_DIR:-$ROOT/artifacts/r562-r1-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
mkdir -p "$OUT"
test -z "$(find "$OUT" -mindepth 1 -maxdepth 1 -print -quit)" || { echo EVIDENCE_DIR_NOT_EMPTY >&2; exit 1; }
export GODOT_SILENCE_ROOT_WARNING=1 BREAKPOINT_RUNTIME_DISABLED=1
ENGINE_SHA=bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
identity(){
    test -z "$(git status --porcelain=v1 --untracked-files=no)"
    test "$(git rev-parse HEAD)" = "$R562_R1_EXPECTED_HEAD"
    test "$(git rev-parse 'HEAD^{tree}')" = "$R562_R1_EXPECTED_TREE"
    test "$(sha256sum "$GODOT_BIN" | cut -d' ' -f1)" = "$ENGINE_SHA"
    test "$("$GODOT_BIN" --version | head -1 | tr -d '\r')" = '4.7.1.stable.double.custom_build.a13da4feb'
    printf 'HEAD=%s\nTREE=%s\nGODOT_VERSION=%s\nGODOT_SHA256=%s\n' "$R562_R1_EXPECTED_HEAD" "$R562_R1_EXPECTED_TREE" '4.7.1.stable.double.custom_build.a13da4feb' "$ENGINE_SHA"
}
run(){
    local label="$1";shift
    timeout --kill-after=5s 1800s "$GODOT_BIN" --headless --path "$ROOT" "$@" >"$OUT/$label.log" 2>&1
    if grep -Eiq 'SCRIPT ERROR|Parse Error|Compile Error|Invalid call|Invalid access|ERROR:' "$OUT/$label.log";then echo "GODOT_ERROR:$label" >&2;exit 1;fi
    echo "$label=PASS"
}
identity >"$OUT/identity-before.txt"
rm -rf "$ROOT/.godot"
run import --editor --import
T=res://tests/research/fabric_bake0
run parse-lifecycle --check-only --script "$T/fabric_r5_6_2_r1_lifecycle_acceptance.gd"
for i in 1 2 3;do run "lifecycle-$i" --script "$T/fabric_r5_6_2_r1_lifecycle_acceptance.gd";done
run r2-regression --script "$T/fabric_r5_6_1_r2_dynamic_aggregate_acceptance.gd"
run com-recovery-regression --script "$T/fabric_r5_6_1_r2_com_recovery_acceptance.gd"
run r1-regression --script "$T/fabric_r5_6_1_canonical_delta_acceptance.gd"
run bridge4-regression --quit-after 2 --script res://tests/research/fabric1/fabric_bridge4_canonical_world_acceptance.gd
identity >"$OUT/identity-after.txt"
python3 scripts/research/fabric_bake0/collect_r5_6_2_r1_evidence.py --root "$OUT" --expected-head "$R562_R1_EXPECTED_HEAD" --expected-tree "$R562_R1_EXPECTED_TREE" --platform linux
(cd "$OUT" && sha256sum *.log identity-before.txt identity-after.txt evidence.json > SHA256SUMS)
echo 'FABRIC_R562_R1_LINUX_EXACT=PASS'
echo "EVIDENCE_DIR=$OUT"
