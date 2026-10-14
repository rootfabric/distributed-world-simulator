#!/usr/bin/env bash
# R5.5 R4 Linux exact research slice. Does not modify closed physics kernels.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
: "${GODOT_BIN:?Set canonical Godot executable via GODOT_BIN}"
: "${R55_EXPECTED_HEAD:?Set frozen product HEAD}"
: "${R55_EXPECTED_TREE:?Set frozen product TREE}"
ENGINE_SHA256=bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
OUT="${R55_EVIDENCE_DIR:-$ROOT/artifacts/fabric-r5-5-r4/$(date -u +%Y%m%dT%H%M%SZ)-$$}"
mkdir -p "$OUT"
test -z "$(find "$OUT" -mindepth 1 -maxdepth 1 -print -quit)" || { echo 'Evidence directory must be empty' >&2; exit 1; }
export GODOT_SILENCE_ROOT_WARNING=1 BREAKPOINT_RUNTIME_DISABLED=1
identity() {
    test -z "$(git status --porcelain=v1 --untracked-files=no)"
    test "$(git rev-parse HEAD)" = "$R55_EXPECTED_HEAD"
    test "$(git rev-parse 'HEAD^{tree}')" = "$R55_EXPECTED_TREE"
    test "$(sha256sum "$GODOT_BIN" | cut -d' ' -f1)" = "$ENGINE_SHA256"
    test "$("$GODOT_BIN" --version | head -n1 | tr -d '\r')" = '4.7.1.stable.double.custom_build.a13da4feb'
    printf 'HEAD=%s\nTREE=%s\nGODOT_SHA256=%s\n' "$R55_EXPECTED_HEAD" "$R55_EXPECTED_TREE" "$ENGINE_SHA256"
}
run() {
    local name="$1"; shift
    timeout --kill-after=5s 1200s "$GODOT_BIN" --headless --path "$ROOT" "$@" > "$OUT/$name.log" 2>&1
    if grep -Ei 'SCRIPT ERROR|Parse Error|Compile Error|Invalid call|Invalid access|ERROR:' "$OUT/$name.log"; then
        echo "Godot script error: $name" >&2
        return 1
    fi
    echo "$name=PASS"
}
identity > "$OUT/identity-before.txt"
rm -rf "$ROOT/.godot"
run import --editor --import
sample=res://tests/research/fabric_bake0/fabric_r5_5_successor_acceptance.gd
adversarial=res://tests/research/fabric_bake0/fabric_r5_5_adversarial_evidence.gd
matrix=res://tests/research/fabric_bake0/fabric_r5_5_prefix_integrity_matrix.gd
source_binding=res://tests/research/fabric_bake0/fabric_r5_5_r4_source_binding_acceptance.gd
for spec in "$sample" "$adversarial" "$matrix" "$source_binding"; do
    run "parse-$(basename "$spec" .gd)" --check-only --script "$spec"
done
for i in 1 2 3; do run "r55-acceptance-$i" --script "$sample"; done
run r55-adversarial --script "$adversarial"
run r55-prefix-matrix --script "$matrix"
run r55-r4-source-binding --script "$source_binding"
python3 - "$OUT" <<'PY_CHECK'
import json, pathlib, re, sys
out = pathlib.Path(sys.argv[1])
def payload(filename, marker):
    text = (out / filename).read_text(errors='replace')
    matches = re.findall(re.escape(marker) + r'({[^\r\n]+})', text)
    assert len(matches) == 1, (filename, 'missing/duplicated payload')
    return json.loads(matches[0]), matches[0]
acc = [payload(f'r55-acceptance-{i}.log', 'FABRIC_R5_5_RESULT=') for i in (1,2,3)]
assert acc[0][1] == acc[1][1] == acc[2][1], 'non-deterministic R5.5 payload'
assert acc[0][0]['checks'] == 35 and acc[0][0]['failures'] == [], 'R5.5 acceptance unexpected'
adv,_ = payload('r55-adversarial.log', 'FABRIC_R5_5_ADVERSARIAL=')
assert adv['checks'] == 36 and not adv['failures'], 'adversarial mismatch'
m,_ = payload('r55-prefix-matrix.log', 'FABRIC_R5_5_PREFIX_MATRIX=')
assert m['checks'] == 208 and m['rejected_mutations'] == 100 and m['rejected_joint_mutations'] == 100 and not m['failures'], 'prefix matrix mismatch'
s,_ = payload('r55-r4-source-binding.log', 'FABRIC_R5_5_R4_SOURCE_RESULT=')
assert s['rejected_attacks'] == 4 and s['checks'] >= 25 and s['full_rederived_success'] and not s['failures'], 'source binding mismatch'
(out/'r55-deterministic-payload.json').write_text(json.dumps(acc[0][0], sort_keys=True, indent=2)+'\n')
(out/'r55-r4-source-binding-payload.json').write_text(json.dumps(s, sort_keys=True, indent=2)+'\n')
print('R55_R4_STRICT_EVIDENCE=PASS')
PY_CHECK
identity > "$OUT/identity-after.txt"
(cd "$OUT" && sha256sum -- * > SHA256SUMS)
echo "R5_5_R4_FOCUSED=PASS"
echo "EVIDENCE_DIR=$OUT"
