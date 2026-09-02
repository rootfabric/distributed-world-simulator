# ECO.EVO7 PERF2.4 R6 — Windows Exact Verification Instruction

Дата: 2026-09-02

Статус:

```text
VALIDATION ONLY
DO NOT MERGE
```

## Exact source subject

```text
branch:
feature/eco-evo7-perf2-4-runtime-optimization-r6

HEAD:
cacc31e50534ecd4e01dbc84e2573bb235cc752c

TREE:
468930cb35d1ea8ef9c0f2cfe07498d9fde072b1

base R5:
e6550f1fe929a9767c34ff64378e9c64761ad925

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
```

R5 is retained because its recruitment cache produced the best STREAM1 result so far.

## R6 hypothesis

R5 profile shows candidate-build remains one of the two dominant STREAM1 phases.

Canonical `LineageExtension.reproduce_bundle()` creates a fresh child bundle for each offspring. Before R6, CandidateKernel immediately performed a second full deep copy of that fresh genome/traits/lineage tree.

R6 changes only optimized STREAM1 ownership handling:

```text
legacy:
fresh reproduction bundle
  -> duplicate(true)
  -> candidate

optimized R6:
fresh reproduction bundle
  -> direct ownership adoption
  -> candidate
```

The canonical reproduction call, mutation formulas, bundle checksum, candidate fields and candidate hash are unchanged.

Legacy retains the historical defensive deep copy.

No biology/research authority file is changed by R6.

The R5 immutable EnvironmentSample recruitment cache remains unchanged.

## R6 diff from R5

Only:

```text
scripts/ecology/perf/eco_evo7_par3_candidate_kernel_v1.gd
scripts/ecology/perf/eco_evo7_stream1_generation_stream_executor_v1.gd
tests/ecology/eco_evo7_perf24_runtime_optimization_acceptance.gd
```

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

## Required campaign

Fresh detached worktree on exact R6 HEAD.

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

Do not modify code/tests/thresholds.
Do not rerun a genuine performance RED to fish for better timing.

## Frozen PERF2.4 acceptance

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

## Required evidence

Return all nine points with:

```text
legacy / optimized wall p50
wall speedup
legacy / optimized STREAM1 p50
STREAM1 speedup
candidate_build_ms
route_build_ms
recruitment_eval_ms
context builds
chunk-local sorts
```

Compare R6 against R5 specifically in candidate_build_ms. The R6 hypothesis is supported only if optimized candidate-build time is consistently lower without canonical parity loss.

PASS requires all frozen gates.

On RED, return the complete nine-point profile for the next repair.
