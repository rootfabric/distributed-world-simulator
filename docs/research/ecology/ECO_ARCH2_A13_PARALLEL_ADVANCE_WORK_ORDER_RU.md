# ECO ARCH2 A13 — Bounded Parallel Advance / Work Order R1

Status: IMPLEMENTATION.

Base:
`c25a6b26d83b937acd1eb4cd4d92e2b44b40c678`
(A13 Bounded Parallel Prepare R1 merged main)

Risk class: MEDIUM — bounded internal runtime scheduling / non-authoritative optimization.

## Problem statement

A13 now performs Phase 1 preparation in bounded worker waves, then joins all workers
before one global resource allocation. Phase 2 still advances every individual
serially after grants are known.

Closed path today:

```text
spatial worksets
→ PARALLEL PREPARE
→ join
→ ONE GLOBAL Field.allocate_demands()
→ SERIAL _advance_individual()
→ canonical population/propagule merge
```

The post-allocation advances are independent once each organism's canonical sample
and allocated intake are fixed.

## Desired behavior

Build a composed opt-in path:

```text
spatial worksets
→ bounded PARALLEL PREPARE
→ join all prepare workers
→ ONE GLOBAL Field.allocate_demands()
→ bounded PARALLEL ADVANCE
→ join all advance workers
→ canonical merge by workset index/member order
→ same canonical field/population/propagule bytes
```

## Safety boundaries

The global allocator remains an absolute barrier:
- no advance worker starts before global allocation succeeds;
- allocation is called exactly once over the complete canonical demand set;
- advance workers cannot mutate Field or shared canonical Runtime state;
- worker completion order is never used as canonical merge order.

## Selected design

- preserve the accepted Parallel Prepare APIs unchanged;
- add a new composed spatial parallel-advance path;
- preparation continues to use the already-verified bounded worker path;
- factor the global allocation into one shared helper;
- factor post-allocation advancement into serial and bounded-parallel strategies;
- explicit advance worker bound: default 4, maximum 8;
- each advance worker receives deep-copied entries, samples and intake values;
- worker output is local: advanced entries + propagules + execution attestation;
- all started workers are joined before result interpretation or return;
- failures are consumed in canonical workset order, preserving serial failure precedence;
- within each workset, member order remains canonical;
- global propagule limit is enforced during canonical merge, in the same order as serial execution;
- final population and propagules retain the existing canonical sorts;
- scheduler/thread telemetry remains result-only and never enters Runtime/checkpoints.

## Affected owners

- A5 lifecycle runtime: adds execution strategy only.
- A4 Field allocator: unchanged authority and implementation.
- Spatial workset plan: unchanged partition owner.
- EcologyRuntime: adds opt-in composed path.
- Activity cadence: adds opt-in composed catch-up sibling.
- persistence/checkpoints: unchanged.

## Non-goals

- parallel resource allocation;
- per-tile resource ownership;
- parallel propagule admission;
- parallel environmental feedback;
- reduced biology / FULL-REDUCED-PATCH;
- changing population limits;
- performance claims before profiling.

## Key equivalence requirement

For the same valid state/options:

```text
serial spatial
==
parallel prepare
==
parallel prepare + parallel advance
```

for canonical field/population/propagule/runtime/checkpoint bytes and hashes.

## Failure semantics

- invalid worker bounds fail before starting worker threads;
- stale spatial plans fail before execution;
- thread-start failure joins all already-started threads;
- worker result/type/index/thread-context mismatches fail closed;
- if multiple workers fail, the error from the first canonical workset is authoritative;
- global propagule overflow is detected during canonical ordered merge;
- no partial canonical state is returned.

## Validation plan

- 256-founder / 16-workset fixture;
- advance worker bounds 1/2/4/8;
- every workset advances off main thread;
- peak advance workers never exceeds configured bound;
- exact equivalence to serial spatial and accepted Parallel Prepare result;
- repeated threaded advance deterministic;
- population permutation invariant;
- invalid prepare/advance bounds fail closed;
- stale plan rejected before workers;
- 8-tick reproduction+mutation runtime byte/hash exact;
- checkpoint bytes identical;
- scheduler/thread metadata absent from canonical Runtime/checkpoints;
- Active/Sleeping exact catch-up composed through full parallel path;
- Windows + Linux exact;
- regress Parallel Prepare, Activity, Spatial, A13 Exact Worksets, A12 and A11.

## Expected risks

1. completion order leaking into population or propagule ordering;
2. global propagule limit semantics drifting from serial path;
3. worker failure precedence becoming timing-dependent;
4. shared mutable Variant data crossing threads;
5. accidental advance before the global allocation barrier;
6. platform-specific Godot Thread behavior.
