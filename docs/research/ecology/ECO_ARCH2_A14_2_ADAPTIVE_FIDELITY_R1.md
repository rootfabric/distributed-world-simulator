# ECO ARCH2 A14.2 — Adaptive Fidelity R1/R2

Status: R2 NARROW TESTS PUBLISHED / FRESH EXACT PENDING. Base main: `fc69771a6a536463010ca880f03c27b3aa66e45e` (A14.1 merge).

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


## A14.2 R2 — narrow adversarial closure (production code unchanged)

- Real REDUCED -> newly active FULL transition: scheduler tick 1/2/3
  is deliberately held back under reduced cadence=4 with identical canonical
  state. At tick=3 (before the cadence boundary) one actually occupied tile
  activates. Advisory mode becomes globally FULL with all 3 debt ticks due.
  Replay output must match a continuous 3-tick baseline in canonical bytes,
  Runtime.state_hash and A8 serialized checkpoint, and must leave source
  untouched. Mode, tile counts and plan validation are checked.
- Real mid-replay failure: reproductive fixture is stepped to the *first*
  naturally failing canonical tick under bounded population pressure.
  Capture the state two ticks earlier; separately confirm tick #1 succeeds
  and creates the expected next canonical state. Now replay both steps in
  Runtime.advance_spatial_fidelity. Tick #2 must surface the same underlying
  error via RUNTIME_FIDELITY_CATCH_UP, return no state or canonical frontier
  and leave original bytes, state hash and A8 checkpoint unchanged.
- Previous invalid-workers falsifier is explicitly labelled *entry-only*:
  it cannot substitute for the new after-one-tick atomicity test.
- Production Adaptive/Fidelity/Runtime/A5 biology is NOT modified.
  No artificial runtime fault-injection seam has been introduced.

R2 test emits ECO_ARCH2_A14_2_ADAPTIVE_R2 PASS alongside original
ECO_ARCH2_A14_2_ADAPTIVE PASS only when all assertions pass.

### Release gates

R2 source publication is not execution evidence. Freeze one exact commit
and independently demonstrate portable Godot smoke + Linux double exact +
Windows double exact + A13 regression, then separate fresh independent
source review and runtime verification. Record HEAD/TREE, Godot hashes,
logs and exit codes. Remain DRAFT and DO NOT MERGE until all gates succeed.
A14.3 CPU Budget & Wake Scheduling stays in a separate follow-on branch.
