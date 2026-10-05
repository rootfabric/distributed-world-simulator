# ECO ARCH2 A13 — Bounded Parallel Prepare / Work Order R1

Status: IMPLEMENTATION.

Base:
`1f8a9debc4f8838569f818faa43bdadc0f23f965`
(A13 Active / Sleeping exact cadence R1 merged main)

Risk class: MEDIUM — bounded internal runtime scheduling / non-authoritative optimization.

## Problem statement

A13 spatial scheduling already partitions the canonical population into deterministic
worksets, but A5 Phase 1 preparation is still executed serially:

```text
workset
→ phenotype compile
→ environment sample
→ demand generation
→ next workset
→ ONE GLOBAL allocation
```

This preserves exact semantics but leaves independent per-workset preparation unable
to use multiple CPU cores.

## Current behavior

A5 owns one canonical lifecycle transition. Its closed invariant is:

```text
canonical population
→ deterministic worksets
→ prepare all demands
→ ONE GLOBAL Field.allocate_demands()
→ advance with grants
→ canonical merge
```

Preparation reads canonical field/population and produces samples + demands. It does
not own resources or mutate canonical state.

## Desired behavior

Add an opt-in bounded parallel preparation path:

```text
canonical spatial worksets
→ bounded worker waves
   ├─ workset prepare
   ├─ workset prepare
   └─ workset prepare
→ join ALL workers
→ canonical merge by workset index
→ ONE GLOBAL Field.allocate_demands()
→ existing SERIAL post-allocation advance
→ same canonical bytes/hashes/checkpoints
```

## Alternatives considered

1. **WorkerThreadPool group tasks.**
   Rejected for R1 because explicit Thread objects make the worker bound, join
   lifecycle, per-task return value, and failure cleanup visible and directly testable.

2. **Parallelize allocation.**
   Rejected. A5 global resource allocation is canonical authority and remains exactly
   one call over the complete demand set.

3. **Parallelize post-allocation advance in the same change.**
   Rejected. That is the next A13 stage and has different deterministic merge/failure
   concerns.

4. **Share mutable preparation containers between workers.**
   Rejected. No Mutex-protected shared samples/demands collector is introduced.

## Selected design

- new A5 spatial parallel-prepare entry point;
- deterministic spatial plan remains the partition source;
- worker bound is explicit, default 4, maximum 8;
- preparation runs in waves with at most `max_prepare_workers` active Thread objects;
- every worker receives deep-copied field + unit entries and owns its local result;
- worker results are joined before allocation;
- completion order is ignored;
- results and failures are consumed strictly in canonical workset index order;
- demand ordering is therefore byte-identical to serial preparation;
- exactly one existing `Field.allocate_demands()` call remains authoritative;
- post-allocation individual advance remains serial/canonical in R1;
- worker/thread metadata is result-only scheduler telemetry and never enters Runtime,
  organism, field or checkpoint truth;
- start failure joins already-started threads before returning fail-closed.

## Affected canonical owners

- A5 `resource_lifecycle_runtime_v1.gd`: lifecycle owner; adds execution strategy only.
- `ecology_runtime_v1.gd`: composition owner; exposes opt-in spatial parallel-prepare tick.
- A4 Field allocation owner: unchanged.
- Spatial workset plan owner: unchanged.
- persistence/checkpoint schemas: unchanged.

## Dependencies

- A13 deterministic exact worksets — CLOSED.
- A13 Spatial Workset Addressing — CLOSED.
- A13 Active/Sleeping exact cadence R1 — CLOSED.

## Non-goals

- parallel allocation;
- parallel post-allocation advance;
- reduced/sleeping biology;
- WorkerThreadPool migration;
- persistent scheduler metadata;
- changing population cap;
- claiming a performance win before profiling evidence.

## Expected risks

1. nondeterministic completion order leaking into demand order;
2. thread lifecycle leak if start/failure cleanup misses `wait_to_finish()`;
3. shared Variant mutation across workers;
4. parallel path drifting from serial failure precedence;
5. accidental second/global allocation;
6. platform-specific threading behavior Windows vs Linux.

## Validation plan

- 256-founder / 16-workset fixture uses >1 worker;
- worker bound 1/2/4/8 all exact-equivalent to serial spatial A5;
- parallel result demand/field/population/propagule semantics equal serial path;
- repeated parallel execution is byte-deterministic;
- population input permutation cannot change result;
- dynamic reproduction+mutation runtime over 8 ticks is byte/hash-identical;
- checkpoint bytes identical;
- parallel scheduler metadata absent from canonical Runtime/checkpoint;
- invalid worker bounds fail closed and leave source state unchanged;
- activity-cadence wake composed through the new parallel path is exact-equivalent;
- Windows + Linux exact;
- regress A13 Activity, A13 Spatial, A13 Exact Worksets, A12 and A11.
