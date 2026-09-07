#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
: "${GODOT_BIN:=$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64}"
export GODOT_BIN GODOT="$GODOT_BIN" BREAKPOINT_RUNTIME_DISABLED=1
mkdir -p "$ROOT/artifacts"
OUT="$(mktemp -d "$ROOT/artifacts/fabric-holdout-r4-exact-XXXXXX")"
export OUT
printf '\n*.gd.uid\n' >> .git/info/exclude
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
  printf 'HOLDOUT_R4_EVIDENCE=%s\n' "$OUT"
}
trap finish EXIT
[[ -x "$GODOT_BIN" ]]
[[ "$("$GODOT_BIN" --version)" == '4.7.1.stable.double.custom_build.a13da4feb' ]]
[[ "$(sha256sum "$GODOT_BIN" | cut -d' ' -f1)" == bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7 ]]
python3 - <<'PY' > "$OUT/freeze-before.json"
from pathlib import Path
import json, sys
sys.path.insert(0, 'scripts/research/fabric_holdout_r4')
from holdout import freeze_check
print(json.dumps(freeze_check(Path.cwd()), sort_keys=True))
PY
printf 'HEAD=%s\nTREE=%s\nRUN=%s\nRUNNER=%s\nGODOT_SHA256=%s\n' "$(git rev-parse HEAD)" "$(git rev-parse 'HEAD^{tree}')" "${GITHUB_RUN_ID:-local}" "${RUNNER_NAME:-local}" "$(sha256sum "$GODOT_BIN" | cut -d' ' -f1)" > "$OUT/identity.txt"
git archive HEAD | gzip -n > "$OUT/source.tar.gz"
git diff --check
: > "$OUT/exits.tsv"
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
run_gate protocol python3 tests/research/fabric1/fabric_holdout_r4_protocol_test.py
# A failed holdout remains failed. Regressions still run and are reported separately.
holdout_exit=0
run_gate holdout python3 scripts/research/fabric_holdout_r4/holdout.py --cases config/research/fabric-holdout-r4-cases.json --provenance config/research/fabric-holdout-r4-provenance.json --godot "$GODOT_BIN" --out "$OUT/measurement" || holdout_exit="$?"
regression_exit=0
if [[ -f "$OUT/measurement/measure-1-000-input.json" ]]; then
  run_gate serialization_observation timeout --kill-after=10s 60s "$GODOT_BIN" --headless --path "$ROOT" --script res://tests/research/fabric1/fabric_holdout_r4_serialization_probe.gd -- "$OUT/measurement/measure-1-000-input.json" "$OUT/serialization-observation.json" || regression_exit=2
fi
export R3_REPLAY_DIR="$OUT/r3-replay"
run_gate r3 timeout --kill-after=10s 300s bash RUN_FABRIC_COMPOSITION_R3_TESTS.sh || regression_exit=2
run_gate r2 timeout --kill-after=10s 300s bash RUN_FABRIC_PHYSICS_R2_TESTS.sh || regression_exit=2
run_gate r1 timeout --kill-after=10s 300s bash RUN_FABRIC_REPAIR_R1_TESTS.sh || regression_exit=2
python3 - <<'PY' > "$OUT/freeze-after.json"
from pathlib import Path
import json, sys
sys.path.insert(0, 'scripts/research/fabric_holdout_r4')
from holdout import freeze_check
print(json.dumps(freeze_check(Path.cwd()), sort_keys=True))
PY
cmp "$OUT/freeze-before.json" "$OUT/freeze-after.json"
[[ -z "$(git status --porcelain=v1 --untracked-files=no)" ]]
printf 'HOLDOUT_EXIT=%s\nREGRESSION_EXIT=%s\n' "$holdout_exit" "$regression_exit" > "$OUT/summary.txt"
[[ "$regression_exit" == 0 ]] || exit 2
exit "$holdout_exit"
