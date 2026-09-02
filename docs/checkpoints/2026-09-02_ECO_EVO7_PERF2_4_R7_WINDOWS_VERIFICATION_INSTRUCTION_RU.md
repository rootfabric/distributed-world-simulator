# ECO.EVO7 PERF2.4 R7 — Windows Exact Verification Instruction

Дата: 2026-09-02

Статус:

```text
VALIDATION ONLY
DO NOT MERGE
```

## Exact source subject

```text
branch:
feature/eco-evo7-perf2-4-runtime-optimization-r7

HEAD:
f38551bdb38864b9941eb6434be68d16d774e1cc

TREE:
040b9826f445324805e49b1327f9915f5d692ef0

base R5:
e6550f1fe929a9767c34ff64378e9c64761ad925

rejected R6:
cacc31e50534ecd4e01dbc84e2573bb235cc752c

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
```

R6 ownership-copy hypothesis was not supported by candidate-build timings, so R7 does not carry that experiment forward.

R7 branches from R5 and retains the R5 immutable EnvironmentSample recruitment cache.

## R7 hypothesis

Immediately before pool hashing, the full candidate array is canonically sorted by `candidate_hash`.

The frozen candidate pool hash then extracts those same candidate hashes and sorts them again.

R7 optimized path replaces only that redundant second sort:

```text
generation boundary:
CandidateKernel.sort_candidates(all_candidates)

legacy:
extract candidate_hash values
sort hashes again
join
sha256

optimized R7:
validate candidate_hash sequence is already monotonic
join existing canonical sequence
sha256
```

The hash payload is required to be byte-identical to the frozen implementation.

R7 acceptance contains:

```text
canonical-order hash == frozen sorter hash
unsorted input -> fail closed
```

Legacy remains on the frozen sorter path.

## R7 diff from R5

Exactly:

```text
scripts/ecology/perf/eco_evo7_par3_candidate_kernel_v1.gd
scripts/ecology/perf/eco_evo7_stream1_generation_stream_executor_v1.gd
tests/ecology/eco_evo7_perf24_runtime_optimization_acceptance.gd
```

No biology/research authority file is changed.

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

Use a fresh detached worktree on exact R7 HEAD.

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

Do not modify runtime, tests, profiler or thresholds.

Do not rerun a genuine performance RED to fish for better timing.

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

## Required evidence

Return all nine comparison points:

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

Because R7 optimizes work outside candidate/route/recruitment phase timers, also return for each point:

```text
stream_total_ms
candidate + route + recruitment subtotal
residual_ms = stream_total_ms - phase subtotal
```

Compare R7 residual against R5/R6 where data is available.

The R7 hypothesis is supported only if canonical parity stays 27/27 and optimized residual/STREAM1 improves without broad legacy slowdown.

## Verdict

PASS:
all correctness and frozen performance requirements green.

RED — CORRECTNESS:
compile/runtime/parity/working-set/hash/source-guard failure.

RED — PERFORMANCE:
campaign completes correctly but any frozen performance gate fails.

BLOCKED:
infrastructure prevents a valid exact run.

On PASS, PERF2.4 may proceed to formal acceptance and PERF2.SIM closure.

On RED, return the complete nine-point profile including residual timing for the next repair.
