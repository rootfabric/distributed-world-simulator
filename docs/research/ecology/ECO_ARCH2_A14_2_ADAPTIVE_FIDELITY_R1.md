# ECO ARCH2 A14.2 — Adaptive Fidelity R1

Status: IMPLEMENTED / EXACT_PENDING. Base main: `fc69771a6a536463010ca880f03c27b3aa66e45e` (A14.1 merge).

## Contract and intentional limitation

New scheduler-only advisory `population_adaptive_fidelity_advice_v1.gd` consumes:
- canonical field/population only for spatial addressing;
- externally supplied active tile addresses (exact currently occupied addresses);
- measured full-tick cost estimate and available CPU budget in integer microseconds;
- scheduler committed/target ticks and reduced cadence.

It emits canonical A13 `Fidelity.create(...)` plan plus recomputable advice metadata, all outside Runtime and checkpoints.

Because A5 has ONE GLOBAL resource allocator, mixed FULL/REDUCED exact execution cannot advance active tiles while inactive tiles accumulate debt. **A14.2 R1 therefore only chooses REDUCED when ALL tiles are inactive AND the estimated tick cost exceeds the budget.** Any active tile forces all FULL. If within budget, all FULL. This is deliberately conservative: budget is advisory, not guaranteed latency enforcement. When REDUCED reaches its cadence, the entirety of debt is replayed through the accepted A13 parallel path.

PATCH is never selected automatically: the exact live population is not evidence for a lossy historical PATCH reconstruction. PATCH requires separately proven A9 external refinement and history provenance; future work must supply this contract rather than invent organism history. Missing/invalid activity addresses or telemetry values fail closed, never silently mean sleeping. Runtime state and biological kernels are unchanged.

No per-tile resource allocator, no extra ecological truth, no partial canonical update. No guarantee of speedup for mixed active worlds until allocation ownership permits genuine safe causal decomposition.

## Acceptance R1

- Four spatial tiles with real organisms; one active address forces all-FULL despite insufficient budget.
- Entirely inactive and over budget produces all-REDUCED with zero-byte defer below cadence and exact full wake; replay hash/bytes must equal continuous execution.
- Under-budget returns all-FULL.
- Permuting active addresses yields identical bytes; duplicate or unknown addresses fail closed.
- Tampered advice/embedded plan, stale population and invalid cost/budget/debt fail closed.
- State before and after advisory planning remains byte-identical.
- Linux and Windows exact gates use canonical Godot 4.7.1 double, with full A13 regression as downstream safety gate.
- Future R2 requires trusted activity input provenance, behavior on pending debt when activity switches to FULL, telemetry smoothing/hysteresis, repeated CPU/RSS evidence and external refinement policy for PATCH.

## Current verification

Source published, exact execution not yet confirmed. PR must remain Draft until portable parser smoke and fresh Windows/Linux double-exact results are captured on the final frozen HEAD. No merge without separate human authorization.
