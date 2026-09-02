# ECO.EVO7 PERF2.4 R8 — Windows Exact Verification Instruction

Дата: 2026-09-03

Статус:

```text
VALIDATION ONLY
DO NOT MERGE
```

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

rejected R7:
f38551bdb38864b9941eb6434be68d16d774e1cc

accepted PERF2.3 predecessor:
4997f7116d0e4ac40ed88fe8a41a7b5029621d71

PERF2.0 contract blob:
b076784f6b4016a0191e937c4e6ada1fe90c783b
```

## Previous exact Windows results

```text
R2 wall/stream: 1.016056 / 1.012797
R3 wall/stream: 1.001754 / 1.004387
R4 wall/stream: 0.990549 / 0.993099
R5 wall/stream: 1.006969 / 1.015529
R6 wall/stream: 1.005588 / 1.016030
R7 wall/stream: 1.006384 / 1.014967
```

R7 redundant candidate-pool re-sort hypothesis was not confirmed: residual changes were noise-level.

R8 returns to the dominant candidate path and retains the useful R5 immutable EnvironmentSample recruitment cache.

## R8 hypothesis

Before R8 every offspring rebuilt and re-hashed the exact same frozen default mutation policy in both:

```text
plant_mutation_lineage_extension_evo7_v1.gd
plant_mutation_lineage_kernel_v1.gd
```

R8 does NOT add a second mutator.

The same canonical call chain remains:

```text
CandidateKernel
    ↓
LineageExtension.reproduce_bundle()
    ↓
Kernel.reproduce()
```

Optimized STREAM1 prepares the exact default policy and canonical hashes once during executor setup.

Prepared mode still performs canonical policy validation every offspring and fails closed unless:

```text
effective_policy == default_policy()
```

The optimization removes only repeated policy construction/deep-copy and repeated second validation + SHA work performed by policy_hash().

Legacy receives no prepared context and follows the historical path.

Mutation coefficients, formulas, event hashes, genome checksums, lineage hashes, bundle checksums and candidate hashes are unchanged.

## R8 diff from R5

```text
RUN_ECO_EVO7_PERF2_4_TESTS.sh
scripts/ecology/perf/eco_evo7_par3_candidate_kernel_v1.gd
scripts/ecology/perf/eco_evo7_stream1_generation_stream_executor_v1.gd
scripts/research/ecology/plant_mutation_lineage_extension_evo7_v1.gd
scripts/research/ecology/plant_mutation_lineage_kernel_v1.gd
tests/ecology/eco_evo7_perf24_runtime_optimization_acceptance.gd
```

The runtime allowlist additionally contains the existing R5 recruitment kernel/route/profiler diffs inherited from the accepted R5 base lineage relative to PERF2.3.

## Required R8 source/correctness evidence

Acceptance must prove:

```text
prepared reproduction context non-empty

prepared EVO7 policy:
validate_policy PASS
canonical recomputed policy_hash == prepared evo7_policy_hash

prepared genome policy:
validate_policy PASS
canonical recomputed policy_hash == prepared kernel policy_hash

malformed prepared EVO7 policy:
canonical validation FAIL

exactly one static func reproduce_bundle(
exactly one static func reproduce(

no reproduce_bundle_fast
no reproduce_fast

prepared paths retain validate_policy(effective_policy)
prepared paths bind effective_policy == default_policy()
```

Full campaign must preserve 27/27 exact legacy↔optimized pairs.

## Godot

Use native Windows double Godot:

```text
C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe

version:
4.7.1.stable.double.custom_build.a13da4feb

SHA-256:
3633C3E609C8CE2F9BAE334A9C7E75C7F974DE3AF0415AB4A8050A625A15A7A5
```

Known repository:

```text
C:\distributed-world-simulator\distributed-world-simulator
```

Known host fingerprint:

```text
7c6e75a4a6e09e500cf92790c2ecdde368e2d54811a973b677dda998af5761a8
```

## Required campaign

Fresh detached worktree on exact R8 HEAD.

Run exactly once:

```text
fresh import
PERF1
STREAM1
PERF2.0
PERF2.1
PERF2.2
PERF2.3
PERF2.4
```

Do not edit runtime/tests/profiler/thresholds.
Do not retry a genuine performance RED for timing luck.

## Frozen acceptance

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

## Required performance evidence

Return all nine comparison points:

```text
legacy / optimized wall p50
wall speedup

legacy / optimized STREAM1 p50
STREAM1 speedup

legacy / optimized candidate_build_ms
legacy / optimized route_build_ms
legacy / optimized recruitment_eval_ms

context builds
chunk-local sorts
```

R8 hypothesis is supported only if optimized candidate_build_ms improves consistently enough to move STREAM1 without canonical parity loss.

Also report aggregate candidate-build delta across all 9 points.

## Verdict

PASS:
all correctness + frozen performance gates green.

RED — CORRECTNESS:
compile/runtime/source-guard/prepared-policy/parity/working-set failure.

RED — PERFORMANCE:
campaign completes correctly but any frozen performance gate fails.

BLOCKED:
infrastructure prevents a valid exact run.

On PASS, PERF2.4 may proceed to formal acceptance and PERF2.SIM closure.

On RED, return complete nine-point candidate/recruitment profile for the next repair.
