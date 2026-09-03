# ECO.EVO7 PERF2.4 R12 — Ubuntu Exact Verification Instruction

Дата: 2026-09-03

Статус:

```text
VALIDATION ONLY
DO NOT MERGE
```

## Exact subject

```text
branch:
feature/eco-evo7-perf2-4-runtime-optimization-r12

HEAD:
840cfcea62ef7192b510235f915b849829654c6c

TREE:
967d674c0ba2349db949193969f16f91553761ea

base R10:
4e886cbd6f7be781dab4912f9559c4b77efd5192

rejected R11:
d56d4c73b82b221c7308fe7df52a13bf38459700

accepted PERF2.3 predecessor:
4997f7116d0e4ac40ed88fe8a41a7b5029621d71

PERF2.0 contract blob:
b076784f6b4016a0191e937c4e6ada1fe90c783b
```

## Why R12 branches from R10

R10 was the best point-stability result:

```text
wall geomean:       1.019914
STREAM1 geomean:    1.045702
improved wall:      8/9
non-regressed wall: 9/9
minimum wall ratio: 0.992436
27/27 exact pairs
```

R11 field adoption regressed wall geomean to 1.015165, so R11 is not carried forward.

## R12 hypothesis

After competition, legacy LS3.4 performs:

```text
core.get_snapshot()             # intermediate post snapshot
  -> full deep copies
  -> use only population_hash + record_count

then immediately:

LS3.4.get_snapshot()
  -> core.get_snapshot()        # second full core snapshot
  -> base records already fresh
  -> records.duplicate(true)    # third records copy layer
```

R12 optimized STREAM1:

```text
post population hash = core.population_hash
post count           = core.records.size()

skip intermediate core.get_snapshot()

LS3.4.get_snapshot()
  -> keep the one required core.get_snapshot()
  -> adopt its already-fresh records array
```

Legacy retains the historical two-snapshot + records-copy behavior.

R10 fresh-survivor adoption remains unchanged.
R11 competition-field adoption is NOT present.

No competition formulas, hashes, mutation formulas, R9 certification, R5 recruitment cache, workload or frozen thresholds change.

## R12 diff from R10

Exactly:

```text
scripts/ecology/shadow/eco_evo7_ls34_local_competition_v1.gd
tests/ecology/eco_evo7_perf24_runtime_optimization_acceptance.gd
```

## Required correctness guards

Must PASS:

```text
R10 fresh survivor ownership guards

R12 optimized snapshot-elision state exists
R12 optimized post hash uses core.population_hash
R12 optimized post count uses core.records.size()
legacy intermediate core.get_snapshot() remains
snapshot elision explicitly gated
legacy LS3.4 records duplicate(true) remains
snapshot-elision state resets fail-closed

R9 prepared-context certification remains PASS

54/54 samples
27/27 exact legacy↔optimized pairs
bounded working set PRESERVED
operation reduction PROVEN
```

## Ubuntu Godot

Use:

```text
$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64
```

Required version:

```text
4.7.1.stable.double.custom_build.a13da4feb
```

Known canonical Linux SHA-256:

```text
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

Measure actual SHA and report it.

## Fresh detached worktree

```bash
set -euo pipefail

REPO="${REPO:-$HOME/distributed-world-simulator}"
BRANCH="feature/eco-evo7-perf2-4-runtime-optimization-r12"
EXPECTED_HEAD="840cfcea62ef7192b510235f915b849829654c6c"
EXPECTED_TREE="967d674c0ba2349db949193969f16f91553761ea"

STAMP="$(date +%Y%m%d-%H%M%S)"
WT="$HOME/dws-perf2-4-r12-ubuntu-$STAMP"

git -C "$REPO" fetch origin --prune
test "$(git -C "$REPO" rev-parse "origin/$BRANCH")" = "$EXPECTED_HEAD"

git -C "$REPO" worktree add --detach "$WT" "$EXPECTED_HEAD"
cd "$WT"

test -z "$(git branch --show-current)"
test "$(git rev-parse HEAD)" = "$EXPECTED_HEAD"
test "$(git rev-parse 'HEAD^{tree}')" = "$EXPECTED_TREE"

git merge-base --is-ancestor   4e886cbd6f7be781dab4912f9559c4b77efd5192 HEAD

test "$(
  git rev-parse HEAD:config/ecology/eco-evo7-perf2-measurement-contract.v1.json
)" = "b076784f6b4016a0191e937c4e6ada1fe90c783b"

rm -rf .godot
test -z "$(git status --porcelain --untracked-files=no)"
```

## Exact campaign

Run exactly once:

```bash
export GODOT_BIN="$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64"

set +e
bash ./RUN_ECO_EVO7_PERF2_4_TESTS.sh 2>&1 | tee perf2-4-r12-ubuntu-exact.log
RUN_RC=${PIPESTATUS[0]}
set -e

echo "RUN_RC=$RUN_RC"
```

Do not rerun a genuine PERF2.4 RED for timing luck.

## Frozen acceptance

```text
samples                           54/54
comparison points                  9/9
legacy<->optimized exact pairs    27/27

wall geomean                      >= 1.02
STREAM1 geomean                   >= 1.03
improved wall points              >= 6/9
non-regressed wall points         9/9
minimum wall ratio                >= 0.97

bounded working set               PRESERVED
operation reduction               PROVEN
optimization_claim                TRUE
serial_crossover_claim            FALSE
```

## Required evidence

Return all nine points with:

```text
legacy/optimized wall p50 + ratio
legacy/optimized STREAM1 p50 + ratio
candidate legacy/optimized if present
route legacy/optimized
recruitment legacy/optimized
context builds
chunk-local sorts
```

Special comparison against R10:

```text
R10 wall geomean       1.019914
R10 STREAM1 geomean    1.045702
R10 improved           8/9
R10 non-regressed      9/9
R10 min wall           0.992436
```

Especially report:

```text
AGE_2 chunk=1
AGE_12 chunk=1
AGE_12 chunk=64
AGE_22 chunk=1
```

R12 is accepted only if every frozen gate passes without rounding or threshold changes.

A valid Ubuntu PASS is sufficient; no Windows run is required.
