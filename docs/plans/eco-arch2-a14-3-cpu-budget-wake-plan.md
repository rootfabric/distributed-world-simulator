# ECO ARCH2 A14.3 — CPU Budget & Wake Scheduling — Plan R1

Base: `main` @ `e98a489b591bb29025ffb69a6dbbf1c87b3b1542` (merge of A14.2, PR #752).
Branch: `feature/eco-arch2-a14-3-cpu-budget-wake-r1`.
Frozen A14.2 identity remains: PRODUCT_HEAD `b2abc2cbba5b496e3d06bb10074dc7d223de8f34`,
PRODUCT_TREE `5e4d23982e381c9aa81327cb2a932544d80b8dd8`.

## Objectives

1. Real CPU budget for the ecological planner: a per-tick wall/model-time budget
   enforced by the scheduler, not advisory-only.
2. Peak-load clamping during replay: catch-up replay must cap per-tick compute
   spikes so a large owed backlog cannot stall the whole simulation loop.
3. Priority wake-up of active regions: regions with pending biological events
   (A14.2 adaptive-fidelity state, active occupancy, owed debt) are woken first.
4. Accumulated compute debt accounting: each skipped/deferred region accrues
   debt; debt is a first-class scheduler input (wake order and budget share).
5. Deterministic budget distribution: the split of budget across regions is a
   pure function of canonical state (no wall-clock, RNG, or host-dependent
   inputs), preserving canonical state and exact replay byte-for-byte.
6. Starvation protection: regions that are repeatedly deferred must gain
   priority monotonically until serviced; no region may be starved indefinitely.

## Constraints

- Canonical state and exact replay are non-negotiable: same input bytes → same
  canonical tick hash, checkpoints, and replay frontier (A14.2 falsifier suite
  must keep passing unchanged).
- No changes to the biological core (models, fidelity semantics, event rules)
  without a separate written justification and review; A14.3 is scheduler-side
  only.
- Windows double build `4.7.1.stable.double.custom_build.a13da4feb`
  (SHA256 `3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5`)
  remains the exact verification engine.

## Falsifiers to define (RED first)

- F1 budget-exhaustion: workload exceeding budget → partial, deterministic
  servicing by debt-weighted priority; deferred regions accrue exactly the owed
  debt; no canonical state drift vs an unbounded reference on serviced ticks.
- F2 starvation: a permanently low-priority region must still be serviced
  within a bounded number of ticks once its debt exceeds the starvation bound.
- F3 replay-peak clamp: a long catch-up replay with heavy owed debt completes
  with per-tick clamped peaks and byte-identical final canonical state.

## Verification gates (same as A14.2)

Portable GitHub CI, Linux double exact, Windows self-hosted double exact,
Project Control, fresh independent Windows verifier — all at one frozen
PRODUCT_HEAD/TREE before PR is readied for merge.


## Implementer R1 — conservative architecture correction

A5 currently has ONE GLOBAL canonical resource allocator. The initial F1
wording about physically servicing only a subset of regions is UNSAFE as an
ecology evolution step. A14.3 R1 therefore must NOT implement region-local
canonical advances or pretend they have taken place.

Implemented split (feature-branch only):
- population_cpu_budget_wake_v1.gd admits at most
  min(global debt, floor(available_budget_us / estimated_full_tick_us),
  max_replay_ticks) COMPLETE global canonical ticks in one call. Its public
  execute method only publishes a valid intermediate canonical tick frontier
  after a whole successful slice; any mid-slice error publishes no state.
  The next invocation must rebuild a Fidelity plan at that new canonical
  frontier for the SAME target tick. Once REDUCED wakes, a FULL continuation
  is required to avoid a cadence-induced stall on residual debt < cadence.
  Inputs/events must be held at the scheduler barrier during catch-up.
- population_wake_priority_v1.gd deterministically grants preparation-only
  opportunities by overdue wait, active flag, pending preparation debt, and
  canonical address. Its output is recomputable and budget-bounded in
  estimated cost credits; it NEVER triggers organism transitions. Starvation
  is bounded only if every requested preparation job individually fits the
  budget and caller advances its epoch/last-served counters honestly.

New falsifiers:
- F1: budget below one estimated full tick → exact defer and no overspend;
  a larger credit window admits a predictable number of full-world ticks.
- F2: active-biased noncanonical preparation queue still services every
  waiting address via overdue priority; forged/duplicate inputs fail closed.
- F3: eight owed canonical ticks replay in four independent 2-tick slices,
  each intermediate frontier and final checkpoint byte-equal to continuous
  execution; one late natural failure aborts its ENTIRE attempted slice.

### Explicit gaps and next gates

The credit model is an EXTERNALLY supplied estimate, not actual CPU usage.
No wall-clock deadline can be guaranteed for an indivisible A5 tick, and no
actual region-selective canonical progress occurs. Profiling, calibrated cost
estimates, stricter per-step guards, lifecycle-level resumable preparation,
and independent region safety proofs are follow-up R2/R3 work, not falsely
claimed R1 achievements.

Run portable parser, Linux double exact, Windows double exact, A14.2
regression, A13 exact regression, Project Control and independent verifier
on the exact frozen HEAD/TREE. Do NOT MERGE until all gates are green.
