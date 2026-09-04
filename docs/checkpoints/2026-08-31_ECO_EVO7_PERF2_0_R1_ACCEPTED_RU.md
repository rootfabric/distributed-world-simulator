# ECO.EVO7 PERF2.0 R1 — ACCEPTED

Дата: 2026-08-31  
Статус: **ACCEPTED / EXACT WINDOWS + CI CLOSURE / PERF2.1 AUTHORIZED**

## Accepted subject

Exact runtime/measurement-contract subject:

```text
HEAD
5994598d317a55ddae2954f943021878a279afc9

branch
feature/eco-evo7-perf2-0-measurement-contract-r1

Godot
4.7.1.stable.double.custom_build.a13da4feb
```

The later merge commit is metadata/integration only:

```text
PR #348
merge
ac69eb49dc0e96568ff7b8109a4c8822efc90c29
```

The accepted identity remains the exact Windows-tested PR HEAD above.

## Evidence chain

Fresh detached Windows verification:

```text
worktree
C:\distributed-world-simulator\eco-perf2-0-r1-final

branch=<detached-head>
head=5994598d317a55ddae2954f943021878a279afc9
suite=perf2.0

PERF1       PASS 69 assertions
STREAM1     PASS 195 assertions
             108 exact comparisons
PERF2.0     PASS 62 assertions

PERF2.0 transitive measurement-contract acceptance PASS
repository-local ECO workflow PASS
exit 0
tracked tree clean
```

The detached-HEAD workflow repair was exercised end-to-end and printed the expected
`branch=<detached-head>` marker without failure.

## Canonical CI closure

```text
workflow
ECO EVO7 PERF2.0 Closure

run
33317717717

exact PR HEAD
5994598d317a55ddae2954f943021878a279afc9

result
SUCCESS
```

The closure performed:

```text
exact PR HEAD checkout
→ exact HEAD assertion
→ exact Godot 4.7.1 double identity
→ fresh project import
→ RUN_ECO_TEST_WORKFLOW.ps1 -Suite perf2.0
→ PERF1
→ STREAM1
→ PERF2.0
→ tracked worktree clean
```

Project Control on the same subject also passed.

## What PERF2.0 accepts

PERF2.0 freezes the measurement semantics for PERF2.SIM:

- workload identity;
- exact workload hash;
- serial↔STREAM1 simulation workload equivalence;
- same-mode comparison identity;
- cross-mode execution comparison identity;
- exact canonical-result parity fence;
- minimum warmup / measured generations / repetitions;
- p50 / p95 / mean / min / max reporting;
- engine allocator memory versus optional external RSS semantics;
- fail-closed rejection of invalid or incomparable measurements.

The contract is noncanonical and side-channel only.

It does **not** create ecology, persistence, network or world authority.

## Correctness invariant

Any later performance result is invalid if canonical ecology differs:

```text
faster + different workbench_hash      = INVALID
faster + different ecology_state_hash  = INVALID
faster + different population_hash     = INVALID
faster + different classification_hash = INVALID
```

Performance claims require exact canonical parity.

## Acceptance decision

All PERF2.0 closure criteria are now satisfied:

```text
exact Godot                         PASS
fresh detached Windows              PASS
PERF1 regression                    PASS 69
STREAM1 regression                  PASS 195 / 108 exact
PERF2.0 focused                     PASS 62
transitive repository workflow      PASS
Project Control                     PASS
canonical Windows CI closure        SUCCESS
tracked tree                        clean
```

Therefore:

```text
ECO.EVO7 PERF2.0 R1 = ACCEPTED
```

## Successor

```text
PERF2.1 — STREAM1 Generation Profiling
AUTHORIZED
```

PERF2.1 must consume the frozen PERF2.0 measurement contract. It may measure and compare
SERIAL_REFERENCE versus STREAM1, chunk sizes and generation-stage costs, but it may not
change measurement semantics or claim an optimization if canonical-result parity fails.

Parallel route remains:

```text
PERF2.SIM
  PERF2.1 → PERF2.2 → PERF2.3 → PERF2.4

VIS4 / PLAY0.MORPH
  continues independently

both accepted
  → PERF2.CONV
  → PLAY1 LIVING REGION
```

PERF2.1 does not wait for PLAY0.MORPH.
