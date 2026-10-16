# ECO ARCH2 A14.4 R1 — Live CPU Budget & Scale Evidence

Base: main 37c2534fc30758c2408c4809c42ccca6e6317e6d (merged A14.3).
Branch: feature/eco-arch2-a14-4-live-budget-profiling-r1.
State: implementation, not independent verified. PR must remain Draft.

## True integration point

A10.5 EcologyWorkbench._process() now chooses the existing canonical
ExperimentController.run_budgeted_to_tick() for real LAB frames. It uses
the accepted A14.3 whole-world replay primitive on the controller's *single*
canonical runtime; never creates or advances a tile-local second truth.
No accepted A5, A6, A13, A14.2, A14.3, Checkpoint, or mutation formula changes.

The old controller.run()/step()/run_to_tick() remain available. WORLD_COMPAT
retains its existing per-tick world authority admission and is not allowed
to use batched A14.4 replay until an independently proven transactional
admission/input barrier is implemented. Generation/condition goals also retain
one-tick stepping, to avoid overshooting a satisfied predicate.

Default LAB workbench settings: budgeted_live_enabled=true,
live_cpu_budget_us=30000, live_max_ticks_per_call=2. The host can call
configure_live_cpu_budget(enabled, budget_us, max_ticks_per_call) to opt out
or adjust. Each frame subtracts only successfully committed ticks from its
logical debt. If credits are insufficient, it retains the backlog exactly.
It never silently performs a too-expensive tick or drops owed simulation
time. The next invocation rebuilds FULL continuation Fidelity on the new
canonical frontier so old REDUCED cadence cannot strand residual debt.

## Real measurements

The new host-side population_budget_live_driver_v1.gd records elapsed time
through the Godot monotonic Time.get_ticks_usec() clock. It reports planning,
execution, total call time, overrun relative to configured credit budget,
committed full ticks and remaining debt. The controller keeps host-local
counters and an integer EWMA cost estimate used only for future scheduling.
The LAB UI status bar shows last measured CPU wall-time, estimated tick
cost, pending debt and overruns. Neither timing values nor telemetry enter
canonical state, checkpoint text, mutation receipts, RNG or biological time.

This is a measured best-effort **estimated credit** budget, not a CPU
preemption feature and NOT a hard wall-time deadline. A5 still has a single
global allocator; one indivisible tick may exceed the configured target.
Region priority from A14.3 remains preparation-only, not independent biology.

## Falsifiers

The real-loop integration test uses the shipped Polygon LAB manifest, runs
legacy Runtime.step and the real budgeted controller in parallel, and
compares exact serialized checkpoint bytes and state hashes at every
2-tick frontier. It also tests zero-credit defer/resume, stage targets
in EcologyWorkbench._process() (5 ticks as 2/2/1 slices), restore with trusted
checkpoint hash, seed invariance, and telemetry exclusion from canonical
persistence.

The scale profile constructs stable populations of 4/32/96/192/256
organisms; 256 is the currently enforced MAX_POPULATION, not a million-scale
world. Three continuous Parallel Advance ticks are compared with three
single-tick measured driver calls, requiring identical state bytes/hash/
checkpoint. Each host logs baseline vs driver elapsed time, measured
execution time and peak/p95 per-slice wall-time as JSON evidence. No speedup
claim is made in advance of this data.

## Acceptance gates

- Godot 4.7.1 official portable parser, live integration and scale PASS.
- Linux and Windows Godot 4.7.1 double exact on same frozen product HEAD:
  live/scale/A14.3/A14.2/A13 and tracked-tree clean.
- Project Control + fresh independent source review and verifier.
- No merge before VERIFIED, no force-push.

## Still outside scope

Actual Earth/WORLD_COMPAT production integration and true preemptible CPU
deadlines require a safe region-level A5 allocator decomposition. The current
256-organism envelope must be extended independently for vast populations.
Host clock telemetry and repeated stress measurements are diagnostics, not
a deterministic scheduling clock or a canonical ecological input.
