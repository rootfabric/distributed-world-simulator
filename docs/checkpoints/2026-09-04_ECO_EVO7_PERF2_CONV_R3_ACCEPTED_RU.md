# ECO.EVO7 PERF2.CONV R3 — ACCEPTED

Дата: 2026-09-04

Статус:

```text
PERF2.CONV R3
ACCEPTED
EXACT LOCAL WINDOWS PASS
PERF2.CONV CLOSED
LS4 AUTHORIZED CURRENT
```

## Exact tested subject

```text
branch
feature/eco-evo7-perf2-conv-stream1-vis4-r3

HEAD
81a0b3fa60664684b02d8387e4693c5f328dbe28

TREE
a192950483267dd428baf2d1daa25de915df2370
```

Acceptance metadata does not replace this tested runtime identity.

## Immutable prerequisites

```text
PERF2.4 R12 runtime
840cfcea62ef7192b510235f915b849829654c6c
TREE 967d674c0ba2349db949193969f16f91553761ea

PERF2.4 accepted control
ab115385e81375b224eb397cf6a9de071bd4e79e

PERF2.4 accepted report hash
16d3407abef3d3ff30cbe4293cb1278e1b18845b0b5332589587d543b134853b

VIS4.9 exact tested
ab44617d8961add81a6c9f245c99d0b68eaeab52
TREE 9d543a3db4f54a676e9f25152785c36a72c56a30
```

Prerequisite policy remained `NO_RERUN_ACCEPTED_IMMUTABLE_EVIDENCE`; the already accepted PERF2.4 timing campaign was not rerolled.

## Exact local witness

```text
OS
Microsoft Windows 10 Pro 10.0.19045

CPU
13th Gen Intel Core i9-13900H, 14C/20T

Godot
4.7.1.stable.double.custom_build.a13da4feb

Godot SHA-256
3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5
```

Fresh detached worktree was created from the exact subject; `.godot` was removed and a fresh headless editor import completed before measurement.

The first orchestration attempt was BLOCKED before measurement because Windows PowerShell 5.1 promoted a harmless native stderr line during fresh import to a terminating `NativeCommandError`. It produced zero samples and no PERF2.CONV artifact. Re-running the same exact subject after removing only the orchestration blocker is therefore an infrastructure retry, not a timing reroll. Exactly one measurement campaign completed.

## Integrated result

```text
PERF2.CONV assertions        930 PASS
measured samples              36 / 36
fresh repetitions              3 / 3
RUN_RC                         0
```

Frozen budgets were not changed or rounded:

| Gate | Frozen requirement | Accepted R3 |
| --- | ---: | ---: |
| p50 combined / simulation | <= 2.50 | 1.517 PASS |
| p95 combined / simulation | <= 4.00 | 1.590 PASS |
| max combined generation | <= 5000 ms | 2501.0 ms PASS |
| max cache entries / record | <= 5 | bounded PASS |
| minimum foreground frames / generation | >= 1 | 104 PASS |

Additional evidence:

```text
p95 combined generation       2206.25 ms
p95 presentation overhead      789.435 ms
maximum cache entries           127
maximum cache lookup entries    127
```

## Correctness / integration invariants

All are GREEN:

```text
stream_contract_green
cache_bounded_green
source_seals_green
single_flight_green
foreground_progress_green
timing_budget_green
```

The exact integrated campaign additionally proved:

```text
optimized STREAM1 only
legacy STREAM1 calls = 0
chunk-local parent sorts = 0
chunk-local candidate sorts = 0
chunk-local route sorts = 0
chunk-local recruitment sorts = 0
max_parent_chunk_seen = 64
source seals exact across all 36 samples
single-flight rejection = 36/36
```

All three fresh repetitions ended at the same ecology state hash:

```text
a873df6e14d6bf78d657fc30f8a72e9c4cda7e3c4a971bf481600f430979d6a1
```

## Earned convergence claims

The integrated report validates all four claims:

```text
PERF2.5  VIS4 materialization profiling      TRUE
PERF2.6  PH5 LOD/cache bounded               TRUE
PERF2.7  STREAM1 + VIS4 integrated load      TRUE
PERF2.8  PLAY1 performance acceptance        TRUE
```

## Report identity

```text
artifact
artifacts/perf2/perf2-conv-stream1-vis4-r1.json

report_hash
1064567c83c1bd023589fdf9e36f8436b9624eeb928e8b7d413b92ce3254c3f6

artifact file SHA-256
9af003d0b1600258ba5aee1f734891a7b425a50995ab668a83b23e10d768c283
```

Final HEAD/TREE were unchanged and tracked worktree status was CLEAN.

## Project Control disclosure

Validation carrier Project Control run `33865957675` passed exact checkout, control candidate syntax/generation and checkpoint-session regression. The architecture/ownership compatibility step remained globally RED from concurrent external drift. This acceptance does not relabel that unrelated global RED as green.

## Decision

```text
PERF2.CONV R3 = ACCEPTED
PERF2.CONV = CLOSED
PERF2.5 = EARNED
PERF2.6 = EARNED
PERF2.7 = EARNED
PERF2.8 = EARNED
```

No production promotion and no new ecology truth authority are created by this acceptance.

The live roadmap had LS4 explicitly deferred behind PERF2 convergence or a separate owner decision. PERF2.CONV is now accepted, so that prerequisite is satisfied.

Next frontier:

```text
ECO.EVO7/LS4
Next ecology complexity stage
AUTHORIZED CURRENT
```

LS4 authorization does not invent an LS4 substage or runtime contract. Those must be frozen separately before implementation.
