# ECO.EVO7 PERF2.4 R10 — Ubuntu Exact Verification Instruction

Дата: 2026-09-03

Статус:

```text
VALIDATION ONLY
DO NOT MERGE
```

## Exact subject

```text
branch:
feature/eco-evo7-perf2-4-runtime-optimization-r10

HEAD:
4e886cbd6f7be781dab4912f9559c4b77efd5192

TREE:
1c2a8972b4a6039d73199c9e686a56c9e480fc5d

base R9:
61b96a5db9e56692da1231df492a450a1fce049a

accepted PERF2.3 predecessor:
4997f7116d0e4ac40ed88fe8a41a7b5029621d71

PERF2.0 contract blob:
b076784f6b4016a0191e937c4e6ada1fe90c783b
```

## R9 exact Ubuntu baseline

```text
wall geomean:       1.02782 PASS
STREAM1 geomean:    1.06113 PASS
improved wall:      5/9 FAIL
non-regressed wall: 8/9 FAIL
minimum wall ratio: 0.96055 at AGE_12 chunk=64 FAIL
exact pairs:        27/27 PASS
candidate:           improved 9/9, mean ratio about 1.085
```

## R10 hypothesis

The R9 failing wall points often had improved STREAM1, so R10 targets post-STREAM1 wall-only copy work.

In LS3.4 competition:

```text
_competition_pass()
  survivors.append(record.duplicate(true))
```

already creates fresh independent survivor records.

Before R10, LS3.4 immediately deep-copied those fresh survivor records again:

```text
core.records = survivors.duplicate(true)
```

R10 optimized STREAM1 adopts the already-fresh survivor array directly.

Legacy keeps the historical second deep copy.

Competition formulas, survival decisions, field hashes, record validation, R9 candidate certification and R5 recruitment caching remain unchanged.

## R10 diff from R9

Exactly:

```text
RUN_ECO_EVO7_PERF2_4_TESTS.sh
scripts/ecology/shadow/eco_evo7_ls34_local_competition_v1.gd
tests/ecology/eco_evo7_perf24_runtime_optimization_acceptance.gd
```

## R10 correctness guards

Must PASS:

```text
competition survivors are created by record.duplicate(true)
explicit optimized survivor-adoption flag exists
adoption limited to OPTIMIZED_GENERATION_BOUNDARY_CANONICALIZATION
optimized path adopts already-fresh survivors
legacy path retains survivors.duplicate(true)
ownership flag resets fail-closed

all R9 prepared-context certification checks remain PASS
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

Fresh detached worktree on exact R10 HEAD.

Run exactly once:

```bash
export GODOT_BIN="$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64"
bash ./RUN_ECO_EVO7_PERF2_4_TESTS.sh 2>&1 | tee perf2-4-r10-ubuntu-exact.log
```

Do not rerun a genuine PERF2.4 performance RED.

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

Special focus:

```text
AGE_12 chunk=64
AGE_2 chunk=7
AGE_12 chunk=1
AGE_22 chunk=7
```

Those were the four R9 non-improved wall points.

R10 succeeds only if point-level wall stability improves while R9 candidate/STREAM1 gains and 27/27 parity remain intact.

## Verdict

PASS:
all correctness and frozen performance requirements green.

RED — CORRECTNESS:
compile/runtime/source-guard/parity/working-set failure.

RED — PERFORMANCE:
campaign completes correctly but any frozen performance requirement fails.

BLOCKED:
infrastructure prevents exact verification.

A valid Ubuntu PASS is sufficient; no Windows run is required.
