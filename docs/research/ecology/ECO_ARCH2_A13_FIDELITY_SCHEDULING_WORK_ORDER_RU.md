# ECO ARCH2 A13 — Fidelity-Aware FULL / REDUCED / PATCH Scheduling / Work Order R1

Status: IMPLEMENTATION_CANDIDATE — PR #744.

Base:
`42dd7de5d9980e4491516fae459d3e0276d2ce8c`
(A13 Bounded Parallel Advance R2 merged main)

Risk class: MEDIUM — scheduler/control semantics over the accepted exact ecology runtime.

## Goal

Add a versioned fidelity-aware scheduling layer over A13 spatial worksets and the
verified Parallel Advance path without creating a second ecology truth or a second
resource allocator.

The fidelity names are inherited from the accepted A9 representation contract:

- **FULL** — exact history retained; canonical execution is immediately eligible.
- **REDUCED** — exact history retained losslessly; scheduler may defer bounded work,
  but execution is still the same exact ecology kernel after wake/refinement.
- **PATCH** — lossy authenticated projection; exact historical individual state is
  not retained and canonical advance therefore requires external exact refinement.

This checkpoint is scheduling/control, not a new approximate biological kernel.

## Execution model

```text
canonical spatial worksets
→ fidelity plan per spatial address
   ├─ FULL     cadence = 1
   ├─ REDUCED  bounded cadence, exact history retained
   └─ PATCH    bounded cadence, exact history NOT retained
→ one global canonical frontier
→ if REDUCED is not due: defer, mutate zero canonical bytes
→ if PATCH is not due: defer, mutate zero canonical bytes
→ if PATCH becomes due: REFINEMENT_REQUIRED, mutate zero canonical bytes
→ after caller restores exact state and reclassifies PATCH as FULL/REDUCED:
   replay complete debt tick-by-tick through verified Parallel Advance
→ same canonical ecology truth
```

## Global coupling invariant

A5 still owns exactly one global resource allocation barrier for the full population.
Therefore FULL tiles cannot be canonically committed ahead of REDUCED/PATCH debt.

No per-tile allocator, no independent tile timeline, no partial canonical publish.

## R1 plan contract

New scheduler schema:
`dws.ecology.fidelity-schedule-plan.v1`

Inputs:
- exact field + population;
- explicit fidelity overrides by existing spatial address;
- committed scheduler tick;
- target scheduler tick;
- REDUCED cadence;
- PATCH cadence;
- spatial tile span / max members.

Unspecified addresses are FULL.

Each plan is bound to:
- field geometry hash;
- population hash;
- spatial plan hash;
- canonical spatial membership.

Per-tile derived fields:
- address;
- fidelity;
- cadence;
- due tick;
- exact_history_retained;
- member/shard counts.

Plan-level derived fields:
- FULL/REDUCED/PATCH counts;
- global_commit_ready;
- catch_up_ticks;
- refinement_required;
- canonical refinement address list.

## Semantics

### FULL

FULL carries exact history and cadence 1. If every tile is FULL, target debt is
replayed immediately and exactly.

### REDUCED

REDUCED is NOT coarse biology. It is exact state retention with deferred execution.
Before the configured cadence, no canonical state changes. At/after cadence, the
entire debt is replayed exactly through `Runtime.step_spatial_parallel_advance()`.

### PATCH

PATCH is lossy and cannot independently execute biology. While its cadence is not
due, the scheduler may accumulate bounded debt with zero canonical mutation.
At/after the PATCH cadence boundary, exact advance returns
`RUNTIME_FIDELITY_REFINEMENT_REQUIRED` before any ecology transition.

The caller must restore an exact external snapshot at the same canonical frontier,
then create a new plan reclassifying that address as FULL or REDUCED. R1 does not
forge historical individuals from PATCH totals/cohorts.

## Safety boundaries

- scheduler metadata never enters Runtime/checkpoints;
- no biological state approximation is introduced;
- no synthetic tick jump;
- no partial catch-up publish;
- every replay tick recomputes spatial worksets;
- every replay tick uses exactly one global allocation;
- PATCH never silently becomes FULL;
- unknown/tampered/stale fidelity plans fail closed;
- bounded debt <= 64;
- cadences are explicit and <= 64;
- input ordering cannot alter plan bytes;
- rendering LOD is out of scope.

## Acceptance

1. Four-tile fixture produces deterministic FULL/REDUCED/PATCH classification.
2. Fidelity override input order and population order cannot change plan bytes.
3. Unknown address / invalid mode / invalid cadence / stale plan reject.
4. All-FULL target tick executes exact canonical progression immediately.
5. Mixed FULL+REDUCED defers below cadence with zero canonical byte mutation.
6. REDUCED wake replays complete debt and is byte/hash/checkpoint exact to
   continuous execution with reproduction+mutation.
7. PATCH below cadence defers with zero canonical mutation.
8. PATCH due returns exact `RUNTIME_FIDELITY_REFINEMENT_REQUIRED` and canonical
   state remains untouched.
9. Reclassifying the externally refined PATCH address to REDUCED/FULL at the same
   frontier allows exact catch-up to the continuous reference.
10. A failed multi-tick replay is atomic.
11. Scheduler schema/modes never appear in Runtime/checkpoint bytes.
12. Parallel Advance, Activity, Parallel Prepare, Spatial, A13, A12 and A11 exact
    regressions pass on the same subject.
13. A9 synthetic fidelity contract is rerun to ensure FULL/REDUCED/PATCH meanings
    remain aligned.

## Non-goals

- active coarse population dynamics;
- cohort evolution law;
- PATCH historical reconstruction;
- AGGREGATE scheduling;
- per-tile resource ownership;
- cross-tile approximate allocation;
- performance claims before profiling/telemetry;
- population ceiling above 256.
