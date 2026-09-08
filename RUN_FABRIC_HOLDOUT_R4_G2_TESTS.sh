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
python3 - <<'PY' > "$OUT/g1-freeze-audit.json"
from pathlib import Path
import hashlib, json, sys
sys.path.insert(0, 'scripts/research/fabric_holdout_r4')
from holdout import freeze_check
root = Path.cwd()
cases = root/'config/research/fabric-holdout-r4-cases.json'
result = freeze_check(root)
result['cases_sha256'] = hashlib.sha256(cases.read_bytes()).hexdigest()
expected = '7e2dd992e372129a7d006ca26fc2666473ca15f5aeeb45d769818cc0216a793f'
result['cases_hash_matches_g2_work_order'] = result['cases_sha256'] == expected
if not result['cases_hash_matches_g2_work_order']:
    raise SystemExit('G1_CASE_BYTES_DRIFT')
print(json.dumps(result, sort_keys=True))
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
run_gate g2 timeout --kill-after=10s 300s "$GODOT_BIN" --headless --path "$ROOT" --script res://tests/research/fabric1/fabric_holdout_r4_g2_acceptance.gd
run_gate r3 timeout --kill-after=10s 300s bash RUN_FABRIC_COMPOSITION_R3_TESTS.sh
run_gate r2 timeout --kill-after=10s 300s bash RUN_FABRIC_PHYSICS_R2_TESTS.sh
run_gate r1 timeout --kill-after=10s 300s bash RUN_FABRIC_REPAIR_R1_TESTS.sh
[[ -z "$(git status --porcelain=v1 --untracked-files=no)" ]]
printf 'G2_TARGETED=PASS\nR3=PASS\nR2=PASS\nR1=PASS\nG1_HISTORY=PRESERVED_FAIL\n' > "$OUT/summary.txt"
