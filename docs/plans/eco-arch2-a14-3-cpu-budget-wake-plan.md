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
