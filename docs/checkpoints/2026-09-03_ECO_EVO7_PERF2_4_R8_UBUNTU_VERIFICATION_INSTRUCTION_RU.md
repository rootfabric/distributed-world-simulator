# ECO.EVO7 PERF2.4 R8 — Ubuntu Exact Verification Instruction

Дата: 2026-09-03

Статус:

```text
VALIDATION ONLY
DO NOT MERGE
```

Этот carrier заменяет Windows verification для R8. Нужен один exact Ubuntu runtime campaign; при валидном Ubuntu PASS отдельный Windows-прогон не требуется.

## Exact source subject

```text
branch:
feature/eco-evo7-perf2-4-runtime-optimization-r8

HEAD:
e1a761faedd7531be36562aeaebed4eeeaa4d3a5

TREE:
53a71ee592f32b759bc3aea382aa954e4a6304b7

base R5:
e6550f1fe929a9767c34ff64378e9c64761ad925

accepted PERF2.3 predecessor:
4997f7116d0e4ac40ed88fe8a41a7b5029621d71

PERF2.0 contract blob:
b076784f6b4016a0191e937c4e6ada1fe90c783b
```

## Canonical Linux Godot

Use the existing project Linux double build, not distro Godot and not Windows/WSL binary:

```text
$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64
```

Required version:

```text
4.7.1.stable.double.custom_build.a13da4feb
```

Record the Linux binary SHA-256 with `sha256sum`. Do not compare it to the Windows SHA.

## Fresh detached worktree

Recommended repository root:

```text
$HOME/distributed-world-simulator
```

If the canonical local clone/worktree root is elsewhere, set REPO to that exact Git checkout; do not clone a different fork.

```bash
set -euo pipefail

REPO="${REPO:-$HOME/distributed-world-simulator}"
BRANCH="feature/eco-evo7-perf2-4-runtime-optimization-r8"

EXPECTED_HEAD="e1a761faedd7531be36562aeaebed4eeeaa4d3a5"
EXPECTED_TREE="53a71ee592f32b759bc3aea382aa954e4a6304b7"
EXPECTED_BASE="4997f7116d0e4ac40ed88fe8a41a7b5029621d71"
EXPECTED_CONTRACT="b076784f6b4016a0191e937c4e6ada1fe90c783b"

GODOT_BIN="$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64"

STAMP="$(date +%Y%m%d-%H%M%S)"
WORKTREE="$HOME/dws-perf2-4-r8-ubuntu-$STAMP"

git -C "$REPO" fetch origin --prune
REMOTE_HEAD="$(git -C "$REPO" rev-parse "origin/$BRANCH")"
test "$REMOTE_HEAD" = "$EXPECTED_HEAD"

git -C "$REPO" worktree add --detach "$WORKTREE" "$EXPECTED_HEAD"
cd "$WORKTREE"
```

## Exact identity

```bash
test -z "$(git branch --show-current)"

HEAD="$(git rev-parse HEAD)"
TREE="$(git rev-parse 'HEAD^{tree}')"

printf 'HEAD=%s\nTREE=%s\n' "$HEAD" "$TREE"

test "$HEAD" = "$EXPECTED_HEAD"
test "$TREE" = "$EXPECTED_TREE"

git merge-base --is-ancestor "$EXPECTED_BASE" HEAD

CONTRACT_BLOB="$(git rev-parse HEAD:config/ecology/eco-evo7-perf2-measurement-contract.v1.json)"
test "$CONTRACT_BLOB" = "$EXPECTED_CONTRACT"
```

## Godot identity

```bash
test -x "$GODOT_BIN"

GODOT_VERSION="$("$GODOT_BIN" --version | head -n1 | tr -d '\r')"
GODOT_SHA256="$(sha256sum "$GODOT_BIN" | awk '{print $1}')"

printf 'Godot=%s\nGodot SHA-256=%s\n' "$GODOT_VERSION" "$GODOT_SHA256"

test "$GODOT_VERSION" = "4.7.1.stable.double.custom_build.a13da4feb"
```

Also record:

```bash
cat /etc/os-release
uname -srm
lscpu | grep -E 'Model name|CPU\(s\)'
```

## Fresh import state

The worktree must be fresh. Before the campaign:

```bash
rm -rf .godot
git status --porcelain --untracked-files=no
```

Tracked output must be empty.

## Exact campaign

R8 already contains the canonical Linux runner:

```text
RUN_ECO_EVO7_PERF2_4_TESTS.sh
```

It performs:

```text
Godot version check
accepted predecessor check
frozen PERF2.0 contract check
runtime allowlist check
Linux host fingerprint
fresh import
PERF1
STREAM1
PERF2.0
PERF2.1
PERF2.2
PERF2.3
PERF2.4
report checks on PASS
final HEAD/TREE
tracked-clean check
```

Run it exactly once:

```bash
export GODOT_BIN="$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64"

set +e
./RUN_ECO_EVO7_PERF2_4_TESTS.sh 2>&1 | tee "perf2-4-r8-ubuntu-exact.log"
RUN_RC=${PIPESTATUS[0]}
set -e

printf 'RUN_RC=%s\n' "$RUN_RC"
```

Do not run the campaign a second time merely because PERF2.4 is RED.

The runner uses `set -euo pipefail`, so a genuine PERF2.4 RED can terminate the script immediately after that gate. This is expected. If the report exists, inspect that report from the same single run; do not rerun PERF2.4.

## Report after PASS or performance RED

Expected artifact:

```text
artifacts/perf2/perf2-4-runtime-optimization-r1.json
```

If it exists:

```bash
REPORT="artifacts/perf2/perf2-4-runtime-optimization-r1.json"
test -s "$REPORT"

python3 - "$REPORT" <<'PY'
import json, sys
p=sys.argv[1]
with open(p, encoding="utf-8") as f:
    r=json.load(f)
s=r["optimization_summary"]

print("schema:", r["schema"])
print("revision:", r["revision"])
print("report_hash:", r["report_hash"])
print("samples:", len(r["samples"]))
print("comparisons:", len(r["comparisons"]))
print("exact_pairs:", s["exact_pairs"])
print("wall_geomean:", s["wall_geomean_speedup"])
print("stream_geomean:", s["stream_geomean_speedup"])
print("improved_wall_points:", s["improved_wall_points"])
print("nonregressed_wall_points:", s["nonregressed_wall_points"])
print("bounded_working_set_preserved:", s["bounded_working_set_preserved"])
print("operation_reduction_proven:", s["operation_reduction_proven"])
print("optimization_claim:", s["optimization_claim"])

for c in r["comparisons"]:
    print(
        "PROFILE",
        c["scale_id"],
        "chunk="+str(c["stream_chunk_size"]),
        "wall="+str(c["wall_speedup_legacy_over_optimized"]),
        "stream="+str(c["stream_speedup_legacy_over_optimized"]),
        "context_reduction="+str(c["context_build_reduction_factor"]),
        "legacy_sorts="+str(c["legacy_chunk_local_sorts_p50"]),
        "optimized_sorts="+str(c["optimized_chunk_local_sorts_p50"]),
    )
PY
```

Also extract/return candidate, route and recruitment p50 timings for all nine points if present in the report samples/comparison payload.

## Frozen acceptance

Do not change:

```text
samples                           54/54
comparison points                  9/9
legacy<->optimized exact pairs    27/27

wall geomean speedup              >= 1.02
STREAM1 geomean speedup           >= 1.03
improved wall points              >= 6/9
non-regressed wall points         9/9
minimum point wall ratio          >= 0.97

bounded working set               PRESERVED
deterministic operation reduction PROVEN
optimization_claim                TRUE
serial_crossover_claim            FALSE
```

## R8 correctness evidence

R8 acceptance must additionally pass:

```text
prepared reproduction context non-empty

prepared EVO7 policy validates
prepared EVO7 hash == canonical recomputation

prepared genome policy validates
prepared genome hash == canonical recomputation

malformed prepared policy fails validation

exactly one reproduce_bundle()
exactly one reproduce()

no reproduce_bundle_fast
no reproduce_fast

prepared path retains validate_policy(effective_policy)
prepared path bound to exact default_policy()
```

Canonical parity remains mandatory:

```text
27/27 exact A/B pairs
```

## Final identity

After the single campaign:

```bash
FINAL_HEAD="$(git rev-parse HEAD)"
FINAL_TREE="$(git rev-parse 'HEAD^{tree}')"

printf 'FINAL HEAD=%s\nFINAL TREE=%s\n' "$FINAL_HEAD" "$FINAL_TREE"

test "$FINAL_HEAD" = "$EXPECTED_HEAD"
test "$FINAL_TREE" = "$EXPECTED_TREE"

TRACKED="$(git status --porcelain --untracked-files=no)"
if [[ -n "$TRACKED" ]]; then
    printf 'TRACKED DIRTY:\n%s\n' "$TRACKED"
    exit 20
fi

echo "tracked status=CLEAN"
```

Untracked `.godot`, `.uid` and generated artifacts are acceptable. Tracked modifications are not.

## Verdict

PASS only if all transitive gates, correctness checks and frozen PERF2.4 performance requirements pass.

If the full campaign is correct but performance thresholds fail:

```text
PERF2.4 R8:
RED — PERFORMANCE THRESHOLD FAILURE
```

Do not retry.

If compile/runtime/parity/prepared-policy/source-guard/working-set fails:

```text
PERF2.4 R8:
RED — CORRECTNESS / REGRESSION FAILURE
```

If infrastructure prevents a valid run:

```text
PERF2.4 R8:
BLOCKED
```

## Required final report

Return:

```text
ECO.EVO7 PERF2.4 R8 — UBUNTU EXACT VERIFICATION

HOST
/etc/os-release
uname
CPU
host fingerprint

SUBJECT
branch <detached-head>
HEAD
TREE
base R5
accepted predecessor
PERF2.0 contract blob

GODOT
path
version
Linux SHA-256

TRANSITIVE GATES
fresh import
PERF1
STREAM1
PERF2.0
PERF2.1
PERF2.2
PERF2.3
PERF2.4

R8 CORRECTNESS
prepared context
prepared policy/hash identity
single canonical mutator guards
27/27 exact pairs
bounded working set

PERFORMANCE
54/54 samples
9/9 points
wall geomean
STREAM1 geomean
improved /9
non-regressed /9
minimum wall ratio
operation reduction
optimization_claim
serial_crossover_claim

NINE PROFILE POINTS
wall legacy/optimized + ratio
STREAM1 legacy/optimized + ratio
candidate legacy/optimized
route legacy/optimized
recruitment legacy/optimized
context builds
chunk-local sorts

REPORT
report hash
RUN_RC
tracked status
FINAL HEAD
FINAL TREE

VERDICT
PASS / RED / BLOCKED
```

On PASS:

```text
PERF2.4 R8 UBUNTU EXACT VERIFICATION COMPLETED: PASS.

Работа закончена.

Следующий шаг:
зафиксировать PERF2.4 ACCEPTED,
закрыть PERF2.SIM
и перейти к PERF2.CONV.
```

On performance RED:

```text
PERF2.4 R8 UBUNTU EXACT VERIFICATION COMPLETED: RED.

Работа закончена.

PERF2.4 остаётся открытым.

Следующий шаг:
передать полный nine-point profile для следующего repair;
frozen thresholds не изменять.
```

On BLOCKED:

```text
PERF2.4 R8 UBUNTU EXACT VERIFICATION NOT COMPLETED: BLOCKED.

Работа не закончена.

Следующий шаг:
устранить только infrastructure blocker
и повторить тот же exact HEAD.
```
