# ECO.EVO7 PERF2.4 R9 — Ubuntu Exact Verification Instruction

Дата: 2026-09-03

Статус:

```text
VALIDATION ONLY
DO NOT MERGE
```

## Exact subject

```text
branch:
feature/eco-evo7-perf2-4-runtime-optimization-r9

HEAD:
61b96a5db9e56692da1231df492a450a1fce049a

TREE:
1c8e183e21a3334881269541d6b8edf45a5efb0a

base R8:
e1a761faedd7531be36562aeaebed4eeeaa4d3a5

base R5:
e6550f1fe929a9767c34ff64378e9c64761ad925

accepted PERF2.3 predecessor:
4997f7116d0e4ac40ed88fe8a41a7b5029621d71

PERF2.0 contract blob:
b076784f6b4016a0191e937c4e6ada1fe90c783b
```

## R8 exact Ubuntu RED baseline

```text
wall geomean:    1.0121
STREAM1 geomean: 1.0283
improved:        7/9
non-regressed:   8/9
min wall ratio:  0.9298 (AGE_22 chunk=7)
exact pairs:     27/27
```

R8 candidate aggregate delta was about -0.94% but mixed.

## R9 hypothesis

R8 prepared exact default mutation policy and hashes, but still repeated `default_policy()` equality and `validate_policy()` checks on every offspring.

R9 certifies the exact prepared context once at optimized chunk boundary.

Certification proves:

```text
EVO7 policy == exact default_policy()
EVO7 validate_policy PASS
EVO7 declared hash == canonical policy_hash(policy)

kernel policy == exact default_policy()
kernel validate_policy PASS
kernel declared hash == canonical policy_hash(policy)

EVO7 nested genome_policy == kernel prepared policy
```

The candidate loop then threads a validated-state flag through the SAME canonical chain:

```text
CandidateKernel
  -> LineageExtension.reproduce_bundle()
  -> Kernel.reproduce()
```

No second/fast mutator exists.

Direct calls with a non-certified prepared context still self-certify and fail closed.

Legacy path is unchanged.

## R9 diff from R8

Exactly:

```text
scripts/ecology/perf/eco_evo7_par3_candidate_kernel_v1.gd
scripts/research/ecology/plant_mutation_lineage_extension_evo7_v1.gd
scripts/research/ecology/plant_mutation_lineage_kernel_v1.gd
tests/ecology/eco_evo7_perf24_runtime_optimization_acceptance.gd
```

Executor and the useful R5 recruitment EnvironmentSample cache are unchanged.

## Ubuntu Godot

Use:

```text
$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64
```

Required:

```text
4.7.1.stable.double.custom_build.a13da4feb
```

Record Linux SHA-256.

Known previous Linux binary SHA-256:

```text
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

Confirm actual value; do not assume.

## Required campaign

Use a fresh detached worktree on exact R9 HEAD.

Run exactly once:

```bash
export GODOT_BIN="$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64"
bash ./RUN_ECO_EVO7_PERF2_4_TESTS.sh 2>&1 | tee perf2-4-r9-ubuntu-exact.log
```

The canonical runner performs:

```text
Godot check
accepted predecessor
PERF2.0 contract
runtime allowlist
host fingerprint
fresh import
PERF1
STREAM1
PERF2.0
PERF2.1
PERF2.2
PERF2.3
PERF2.4
report/final identity on PASS
```

Do not retry a genuine PERF2.4 performance RED.

If the runner exits at PERF2.4 FAIL but the report exists, inspect that report from the same run.

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

## R9-specific correctness

Must PASS:

```text
prepared context exists
prepared context certification PASS

valid-but-nondefault prepared EVO7 policy -> certification FAIL
prepared EVO7 hash tamper -> certification FAIL

single reproduce_bundle()
single reproduce()

no reproduce_bundle_fast
no reproduce_fast

27/27 exact A/B parity
working set PRESERVED
```

## Required performance evidence

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

Also return:

```text
aggregate candidate delta
candidate improvement consistency
AGE_22 chunk=7 detailed point
```

The R9 hypothesis is supported only if candidate cost improves materially while 27/27 parity remains green.

## Verdict

PASS:
all correctness and frozen performance gates green.

RED — CORRECTNESS:
compile/runtime/certification/parity/working-set/source-guard failure.

RED — PERFORMANCE:
full correct campaign but any frozen performance gate fails.

BLOCKED:
infrastructure prevents an exact run.

A valid Ubuntu PASS is sufficient; Windows verification is not required.
