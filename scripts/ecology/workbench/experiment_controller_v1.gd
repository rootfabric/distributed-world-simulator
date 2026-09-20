# EcologyWorkbench ExperimentController v1 (skeleton, P0).
# Role: single orchestration point of a polygon experiment: RUN/PAUSE,
#   single tick / bounded step / run-to-horizon, RESET to manifest,
#   checkpoint / restore / fork / replay. The ONLY component allowed to call
#   the canonical mutation step (one canonical mutation step per session).
# Layer: 2 (SIMULATION / ORCHESTRATION).
# Canonical API used (owner map rows 3,5,6,7,9):
#   - resource_lifecycle_runtime_v1.gd: step_population(), individual(),
#     materialize_propagule()  [A5]
#   - persistent_environmental_feedback_v1.gd: advance(), create()  [A6]
#   - local_environment_field_v1.gd: create()/advance_tick()/set_cell_signals()
#     (explicit editor inputs only, via owner_token/epoch/revision)  [A4]
#   - observatory_session_v1.gd: start()/advance()/observe()/save_text()/
#     load_text()  [A7/A8]
#   - snapshot_seam_v1.gd: start()/apply()/load_text()  [A8; WORLD-COMPAT]
# Threading rules (architecture doc §3): one canonical mutation step per
#   session; publish only completed immutable snapshots; abort = join;
#   race fail-closed.
# Forbidden: no own lifecycle/reproduction/resource formulas.
class_name EcoWorkbenchExperimentControllerV1
extends RefCounted

var last_error := "NOT_STARTED"

## Start a new run from a validated manifest. Fails closed on invalid input.
func start(manifest: Dictionary) -> bool:
	return false

## Advance exactly one canonical tick (lifecycle + feedback, then publish).
func step() -> bool:
	return false

## Bounded multi-step; abort semantics = join current step, not mid-step cancel.
func run_bounded(ticks: int) -> bool:
	return false

## Checkpoint via A8 (observatory session text + seam hashes).
func checkpoint() -> Dictionary:
	return {}

## Restore / fork: restore continues the same history; fork creates a new
## explicitly linked branch history from the same immutable source.
func restore(checkpoint_text: String) -> bool:
	return false
