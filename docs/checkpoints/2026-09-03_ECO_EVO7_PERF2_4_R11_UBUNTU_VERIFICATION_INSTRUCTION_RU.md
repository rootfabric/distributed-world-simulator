# ECO.EVO7 PERF2.4 R11 — Ubuntu Exact Verification Instruction

Дата: 2026-09-03

Статус:

```text
VALIDATION ONLY
DO NOT MERGE
```

## Exact subject

```text
branch:
feature/eco-evo7-perf2-4-runtime-optimization-r11

HEAD:
d56d4c73b82b221c7308fe7df52a13bf38459700

TREE:
edb4adb628050d6f70976d1795e5dd283812c3d1

base R10:
4e886cbd6f7be781dab4912f9559c4b77efd5192

accepted PERF2.3 predecessor:
4997f7116d0e4ac40ed88fe8a41a7b5029621d71

PERF2.0 contract blob:
b076784f6b4016a0191e937c4e6ada1fe90c783b
```

## R10 exact Ubuntu baseline

```text
wall geomean:       1.019914 FAIL (< 1.02 by 0.000086)
STREAM1 geomean:    1.045702 PASS
improved wall:      8/9 PASS
non-regressed wall: 9/9 PASS
minimum wall ratio: 0.992436 PASS
exact pairs:        27/27 PASS
working set:        PRESERVED
operation reduction: PROVEN
```

R10 fixed all point-level wall gates. Only frozen wall geomean remained microscopically below 1.02.

## R11 hypothesis

R10 removed the redundant second deep copy of fresh survivor records after competition.

R11 targets the adjacent post-STREAM1 copy:

```text
_competition_pass()
    -> constructs fresh local competition field
    -> validates field + hashes
    -> returns field

legacy:
    returned fresh field
      -> Dictionary(...).duplicate(true)
      -> last_competition_field

optimized R11:
    returned fresh field
      -> direct ownership adoption
      -> last_competition_field
```

The field contains evaluations/water arrays and can be non-trivial in size.

R11 changes only ownership transfer. Competition formulas, survival decisions, field construction, field hash, validation, R10 survivor adoption, R9 candidate certification and R5 recruitment cache are unchanged.

## R11 diff from R10

Exactly:

```text
scripts/ecology/shadow/eco_evo7_ls34_local_competition_v1.gd
tests/ecology/eco_evo7_perf24_runtime_optimization_acceptance.gd
```

## R11 correctness guards

Must PASS:

```text
competition field is constructed as a fresh local value
explicit optimized field-adoption flag exists
field adoption limited to optimized STREAM1 mode
optimized path adopts fresh competition field
legacy path retains field duplicate(true)
field ownership flag resets fail-closed

all R10 survivor ownership guards PASS
all R9 prepared-context certification guards PASS
27/27 exact A/B pairs
working set PRESERVED
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

Previous canonical Linux SHA-256:

```text
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

Measure and report actual SHA.

## Required campaign

Fresh detached worktree on exact R11 HEAD.

Recommended setup:

```bash
set -euo pipefail

REPO="${REPO:-$HOME/distributed-world-simulator}"
BRANCH="feature/eco-evo7-perf2-4-runtime-optimization-r11"
EXPECTED_HEAD="d56d4c73b82b221c7308fe7df52a13bf38459700"
EXPECTED_TREE="edb4adb628050d6f70976d1795e5dd283812c3d1"

STAMP="$(date +%Y%m%d-%H%M%S)"
WT="$HOME/dws-perf2-4-r11-ubuntu-$STAMP"

git -C "$REPO" fetch origin --prune
test "$(git -C "$REPO" rev-parse "origin/$BRANCH")" = "$EXPECTED_HEAD"

git -C "$REPO" worktree add --detach "$WT" "$EXPECTED_HEAD"
cd "$WT"

test -z "$(git branch --show-current)"
test "$(git rev-parse HEAD)" = "$EXPECTED_HEAD"
test "$(git rev-parse 'HEAD^{tree}')" = "$EXPECTED_TREE"

rm -rf .godot
test -z "$(git status --porcelain --untracked-files=no)"
```

Run exactly once:

```bash
export GODOT_BIN="$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64"

set +e
bash ./RUN_ECO_EVO7_PERF2_4_TESTS.sh 2>&1 | tee perf2-4-r11-ubuntu-exact.log
RUN_RC=${PIPESTATUS[0]}
set -e

echo "RUN_RC=$RUN_RC"
```

Do not retry a genuine PERF2.4 performance RED for timing luck.

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

Return all nine points:

```text
AGE_2  chunk=1/7/64
AGE_12 chunk=1/7/64
AGE_22 chunk=1/7/64
```

For each:

```text
legacy/optimized wall p50 + ratio
legacy/optimized STREAM1 p50 + ratio
legacy/optimized candidate_build_ms
legacy/optimized route_build_ms
legacy/optimized recruitment_eval_ms
context builds
chunk-local sorts
```

Compare R11 against R10 especially for wall.

R10 baseline points:

```text
AGE_2 c1   1.0085
AGE_2 c7   1.0377
AGE_2 c64  1.0456
AGE_12 c1  1.0172
AGE_12 c7  1.0175
AGE_12 c64 1.0301
AGE_22 c1  0.9924
AGE_22 c7  1.0133
AGE_22 c64 1.0179
```

Special attention:

```text
wall geomean
AGE_22 chunk=1 (only R10 non-improved point)
AGE_12 chunk=1
AGE_12 chunk=7
AGE_22 chunk=7
AGE_22 chunk=64
```

R11 is accepted only if all frozen gates PASS; no threshold may be rounded or weakened.

## Final identity

```bash
test "$(git rev-parse HEAD)" = "$EXPECTED_HEAD"
test "$(git rev-parse 'HEAD^{tree}')" = "$EXPECTED_TREE"

TRACKED="$(git status --porcelain --untracked-files=no)"
test -z "$TRACKED"

echo "tracked status=CLEAN"
```

## Verdict

PASS:
all correctness and frozen performance requirements green.

RED — CORRECTNESS:
compile/runtime/source-guard/parity/working-set failure.

RED — PERFORMANCE:
full correct campaign but any frozen performance gate fails.

BLOCKED:
infrastructure prevents exact verification.

A valid Ubuntu PASS is sufficient; no Windows run is required.
