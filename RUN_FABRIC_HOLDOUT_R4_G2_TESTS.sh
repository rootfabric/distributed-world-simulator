#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
: "${GODOT_BIN:=$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64}"
export GODOT_BIN GODOT="$GODOT_BIN" BREAKPOINT_RUNTIME_DISABLED=1
mkdir -p "$ROOT/artifacts"
OUT="$(mktemp -d "$ROOT/artifacts/fabric-holdout-r4-g2-exact-XXXXXX")"
export OUT
EXCLUDE="$(git rev-parse --git-path info/exclude)"
mkdir -p "$(dirname "$EXCLUDE")"
grep -Fqx '*.gd.uid' "$EXCLUDE" 2>/dev/null || printf '\n*.gd.uid\n' >> "$EXCLUDE"
finish() {
  local code="$?"
  printf 'RUN_EXIT=%s\n' "$code" > "$OUT/run-exit.txt"
  python3 - <<'PY'
from pathlib import Path
import hashlib, os
out = Path(os.environ['OUT'])
with (out/'evidence.sha256').open('w') as stream:
    for path in sorted(out.rglob('*')):
        if path.is_file() and path.name != 'evidence.sha256':
            stream.write(hashlib.sha256(path.read_bytes()).hexdigest()+'  '+path.relative_to(out).as_posix()+'\n')
PY
  printf 'HOLDOUT_R4_G2_EVIDENCE=%s\n' "$OUT"
}
trap finish EXIT
[[ -x "$GODOT_BIN" ]]
[[ "$("$GODOT_BIN" --version)" == '4.7.1.stable.double.custom_build.a13da4feb' ]]
[[ "$(sha256sum "$GODOT_BIN" | cut -d' ' -f1)" == bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7 ]]
printf 'HEAD=%s\nTREE=%s\nRUN=%s\nRUNNER=%s\nGODOT_SHA256=%s\n' "$(git rev-parse HEAD)" "$(git rev-parse 'HEAD^{tree}')" "${GITHUB_RUN_ID:-local}" "${RUNNER_NAME:-local}" "$(sha256sum "$GODOT_BIN" | cut -d' ' -f1)" > "$OUT/identity.txt"
git archive HEAD | gzip -n > "$OUT/source.tar.gz"
git diff --check

# G1 is deliberately a historical FAIL. Do not call its freeze_check against
# a legal G2 production repair: that checker is supposed to reject any runtime
# mutation. Instead prove that every frozen challenge/instrument byte remains
# exactly the same as the preserved G1 status HEAD, and verify the independent
# author/provenance hashes directly.
G1_STATUS_HEAD=b88004e77a9a424f1b23ba979f5ce8883a98f1a8
G1_RUNTIME_HEAD=fd6e83b35301d7a15e92c55939654f1f95729730
G1_RUNTIME_TREE=314330d717db059cd9b9db32c5d6150097e1f2c3
G1_MEASUREMENT_HEAD=9bb354c31d65600eccd6df713118e11a1f26f548
for commit in "$G1_STATUS_HEAD" "$G1_RUNTIME_HEAD" "$G1_MEASUREMENT_HEAD"; do
  git cat-file -e "$commit^{commit}"
done
[[ "$(git rev-parse "$G1_RUNTIME_HEAD^{tree}")" == "$G1_RUNTIME_TREE" ]]
FROZEN_G1_PATHS=(
  config/research/fabric-holdout-r4-cases.json
  config/research/fabric-holdout-r4-provenance.json
  scripts/research/fabric_holdout_r4/holdout.py
  tests/research/fabric1/fabric_holdout_r4_probe.gd
  tests/research/fabric1/fabric_holdout_r4_protocol_test.py
  tests/research/fabric1/fabric_holdout_r4_serialization_probe.gd
  docs/research/FABRIC_HOLDOUT_R4_AUTHOR_RAW_RU.md
)
git diff --exit-code "$G1_STATUS_HEAD" -- "${FROZEN_G1_PATHS[@]}" > "$OUT/g1-frozen-diff.txt"
python3 - <<'PY' > "$OUT/g1-freeze-audit.json"
from pathlib import Path
import hashlib, json
root = Path.cwd()
provenance = json.loads((root/'config/research/fabric-holdout-r4-provenance.json').read_text())
def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
cases_sha = digest(root/'config/research/fabric-holdout-r4-cases.json')
raw_path = root/provenance['raw_response_path']
raw_sha = digest(raw_path)
expected_cases = '7e2dd992e372129a7d006ca26fc2666473ca15f5aeeb45d769818cc0216a793f'
if cases_sha != expected_cases or cases_sha != provenance['cases_sha256']:
    raise SystemExit('G1_CASE_BYTES_DRIFT')
if raw_sha != provenance['raw_response_sha256']:
    raise SystemExit('G1_AUTHOR_RAW_BYTES_DRIFT')
print(json.dumps({
    'g1_historical_verdict': 'EXPERIMENT_COMPLETED_FAIL/FALSIFIED',
    'cases_sha256': cases_sha,
    'cases_hash_matches': True,
    'raw_response_path': provenance['raw_response_path'],
    'raw_response_sha256': raw_sha,
    'raw_response_hash_matches': True,
    'challenge_author': provenance['author'],
    'challenge_author_id': provenance['author_id'],
    'freeze_commit': provenance['freeze_commit'],
    'measurement_subject': provenance['subject_head'],
    'frozen_paths_byte_identical_to_g1_status_head': True,
}, sort_keys=True))
PY

: > "$OUT/exits.tsv"
: > "$OUT/commands.tsv"
run_gate() {
  local name="$1"
  shift
  printf '%s\t' "$name" >> "$OUT/commands.tsv"
  printf '%q ' "$@" >> "$OUT/commands.tsv"
  printf '\n' >> "$OUT/commands.tsv"
  set +e
  "$@" > "$OUT/$name.log" 2>&1
  local code="$?"
  set -e
  printf '%s\t%s\n' "$name" "$code" >> "$OUT/exits.tsv"
  cat "$OUT/$name.log"
  if [[ "$code" != 0 ]]; then return "$code"; fi
  if grep -Eiq 'SCRIPT ERROR|Parse Error|Invalid call|Invalid access|Assertion failed|ERROR:|Segmentation fault' "$OUT/$name.log"; then return 2; fi
}
run_gate import timeout --kill-after=10s 180s "$GODOT_BIN" --headless --editor --path "$ROOT" --import
run_gate g2_bond_id timeout --kill-after=10s 120s "$GODOT_BIN" --headless --path "$ROOT" --script res://tests/research/fabric1/fabric_holdout_r4_g2_bond_id_acceptance.gd
run_gate g2_transport timeout --kill-after=10s 120s "$GODOT_BIN" --headless --path "$ROOT" --script res://tests/research/fabric1/fabric_holdout_r4_g2_transport_acceptance.gd
run_gate g2 timeout --kill-after=10s 300s "$GODOT_BIN" --headless --path "$ROOT" --script res://tests/research/fabric1/fabric_holdout_r4_g2_acceptance.gd
run_gate g2_signed_effort timeout --kill-after=10s 120s "$GODOT_BIN" --headless --path "$ROOT" --script res://tests/research/fabric1/fabric_holdout_r4_g2_signed_effort_acceptance.gd
run_gate r3 timeout --kill-after=10s 300s bash RUN_FABRIC_COMPOSITION_R3_TESTS.sh
run_gate r2 timeout --kill-after=10s 300s bash RUN_FABRIC_PHYSICS_R2_TESTS.sh
run_gate r1 timeout --kill-after=10s 300s bash RUN_FABRIC_REPAIR_R1_TESTS.sh
[[ -z "$(git status --porcelain=v1 --untracked-files=no)" ]]
printf 'G2_BOND_ID=PASS\nG2_TRANSPORT=PASS\nG2_TARGETED=PASS\nG2_SIGNED_EFFORT=PASS\nR3=PASS\nR2=PASS\nR1=PASS\nG1_HISTORY=PRESERVED_FAIL\n' > "$OUT/summary.txt"
