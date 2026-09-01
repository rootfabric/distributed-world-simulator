# ECO.EVO7 PERF2.4 R5 — Windows Exact Verification Instruction

Дата: 2026-09-02

Статус:

```text
VALIDATION ONLY
DO NOT MERGE
```

## Exact source subject

```text
branch:
feature/eco-evo7-perf2-4-runtime-optimization-r5

HEAD:
e6550f1fe929a9767c34ff64378e9c64761ad925

TREE:
edfd2ffeb3848f9ba1cdb6b4948f2be101c06ffb

base R2:
8c022eaea2dd6253b3fd27a84d3db3e88c51d5a3

rejected R3:
df257dc0b717a898b2a92f77d73997f797be801d

rejected R4:
c81e6efb4460e6aa8ea743df9d0ca9651e42bea3

accepted PERF2.3 predecessor:
4997f7116d0e4ac40ed88fe8a41a7b5029621d71

PERF2.0 contract blob:
b076784f6b4016a0191e937c4e6ada1fe90c783b
```

## Previous exact Windows results

```text
R2 wall/stream:
1.016056 / 1.012797

R3 wall/stream:
1.001754 / 1.004387

R4 wall/stream:
0.990549 / 0.993099
```

R5 branches from R2, the best exact baseline.

## R5 hypothesis

The nine R4 profile points show candidate + recruitment dominate STREAM1 time while route time is small. R5 does not continue the R3/R4 ordering/allocation experiments.

R5 caches only the immutable canonical EnvironmentSample used by recruitment observations.

The optimized executor owns a cache with these rules:

```text
identity fence:
revision + environment_seed + environment_field_hash

cache key:
environment cell_hash

bound:
cache.size <= environment_cells.size
```

On cache miss the canonical EnvironmentSample create+validate path is executed.

On cache hit only that already validated immutable EnvironmentSample is reused.

Candidate-specific observation_id, observation_hash, Shadow evaluation, recruitment probability/gate/event and recruitment_event_hash are still recomputed normally.

Legacy mode is not supplied the cache.

## Runtime allowlist

The accepted PERF2.4 allowlist is expanded only by the existing shared pure recruitment kernel:

```text
scripts/ecology/perf/eco_evo7_stream1_generation_stream_executor_v1.gd
scripts/ecology/perf/eco_evo7_par3_candidate_kernel_v1.gd
scripts/ecology/perf/eco_evo7_stream1_route_kernel_v1.gd
scripts/ecology/perf/eco_evo7_perf24_runtime_optimization_profiler_v1.gd
scripts/ecology/perf/eco_evo7_par0_recruitment_kernel_v1.gd
```

No other ecology/research runtime diff is authorized.

## Godot

```text
4.7.1.stable.double.custom_build.a13da4feb
```

Canonical Windows binary previously verified:

```text
C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe

SHA-256:
3633C3E609C8CE2F9BAE334A9C7E75C7F974DE3AF0415AB4A8050A625A15A7A5
```

Known Windows repository path:

```text
C:\distributed-world-simulator\distributed-world-simulator
```

## Required campaign

Use a fresh detached worktree on the exact R5 source HEAD.

Run once:

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

Do not modify code, thresholds or tests in the verification worktree.
Do not repeat a genuine performance RED to fish for a better timing result.

## Frozen PERF2.4 acceptance

```text
samples                          54/54
comparison points                 9/9
legacy<->optimized exact pairs   27/27

wall geomean speedup             >= 1.02
STREAM1 geomean speedup          >= 1.03

improved wall points             >= 6/9
non-regressed wall points        9/9
minimum point wall ratio         >= 0.97

bounded working set              PRESERVED
deterministic operation reduction PROVEN
optimization_claim               TRUE
serial_crossover_claim           FALSE
```

## Required R5 evidence

Return all nine comparison points, including:

```text
legacy / optimized wall p50
wall speedup

legacy / optimized STREAM1 p50
STREAM1 speedup

candidate_build_ms
route_build_ms
recruitment_eval_ms

context reduction
legacy / optimized chunk-local sorts
```

Also compare the R5 summary against R2/R3/R4.

A performance PASS must come from lower optimized timings, not an obvious broad slowdown of the legacy baseline.

## Verdict

PASS:
all correctness and frozen performance requirements green.

RED — CORRECTNESS:
compile/runtime/parity/working-set or invariant failure.

RED — PERFORMANCE:
campaign completes correctly but any frozen performance gate fails.

BLOCKED:
infrastructure prevents a valid exact run.

On PASS, PERF2.4 may proceed to formal acceptance and PERF2.SIM closure.

On RED, return the first correctness failure or the complete nine-point performance profile for the next repair.
