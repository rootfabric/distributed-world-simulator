extends RefCounted
## ECO ARCH2 A14.3 R1 — noncanonical bounded WHOLE-WORLD exact replay.
##
## A5 has one global resource-allocation barrier. Never advance one tile in
## isolation. Each accepted slice consists solely of complete canonical ticks.
## Tick cost is an EXTERNAL estimate; this is an estimated-credit bound and a
## deterministic tick-count clamp, NOT a hard wall-clock execution deadline.
## The accepted A14.2 Runtime.advance_spatial_fidelity remains unchanged.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Fidelity = preload("res://scripts/research/ecology/v2/population_fidelity_schedule_plan_v1.gd")
const Runtime = preload("res://scripts/research/ecology/v2/ecology_runtime_v1.gd")
const Lifecycle = preload("res://scripts/research/ecology/v2/resource_lifecycle_runtime_v1.gd")

const SCHEMA := "dws.ecology.cpu-budget-replay-plan.v1"
const MAX_BUDGET_US := 1000000000
const MAX_ESTIMATE_US := 1000000000
const DEFAULT_MAX_REPLAY_TICKS := 2
const PLAN_KEYS := [
	"schema", "source_state_hash", "fidelity_plan",
	"fidelity_plan_hash", "committed_tick", "target_tick", "debt_ticks",
	"estimated_tick_us", "budget_us", "max_replay_ticks",
	"allowed_ticks", "estimated_spend_us", "remaining_debt_ticks",
	"ready", "refinement_required", "reason",
]

static func create(state: Dictionary, fidelity_plan: Dictionary,
		estimated_full_tick_us: int, budget_us: int,
		max_replay_ticks: int = DEFAULT_MAX_REPLAY_TICKS) -> Dictionary:
	var plan := _build(state, fidelity_plan,
		estimated_full_tick_us, budget_us, max_replay_ticks)
	if plan.is_empty():
		return {}
	return plan if validate(plan, state).is_empty() else {}


static func validate(value: Variant, state: Dictionary) -> String:
	if not C.keys(value, PLAN_KEYS) or String(value.schema) != SCHEMA:
		return "CPU_BUDGET_PLAN_SCHEMA"
	if not value.fidelity_plan is Dictionary:
		return "CPU_BUDGET_PLAN_FIDELITY_TYPE"
	if not C.integer(value.estimated_tick_us, 1, MAX_ESTIMATE_US) \
			or not C.integer(value.budget_us, 1, MAX_BUDGET_US) \
			or not C.integer(value.max_replay_ticks, 1, Fidelity.MAX_CATCH_UP_TICKS):
		return "CPU_BUDGET_PLAN_LIMITS"
	var expected := _build(
		state, value.fidelity_plan,
		int(value.estimated_tick_us), int(value.budget_us),
		int(value.max_replay_ticks))
	if expected.is_empty():
		return "CPU_BUDGET_PLAN_INVALID_SOURCE"
	if C.encode(expected) != C.encode(value):
		return "CPU_BUDGET_PLAN_CONTENT"
	return ""


static func execute(state: Dictionary, options: Dictionary, budget_plan: Dictionary,
		max_prepare_workers: int = 4, max_advance_workers: int = 4) -> Dictionary:
	# Reject invalid worker bounds before zero-budget / zero-debt early exit.
	# Match canonical Runtime's fail-closed entry contract on EVERY path.
	if not Lifecycle.valid_parallel_prepare_workers(max_prepare_workers):
		return _fail("CPU_BUDGET_PARALLEL_PREPARE_WORKERS")
	if not Lifecycle.valid_parallel_advance_workers(max_advance_workers):
		return _fail("CPU_BUDGET_PARALLEL_ADVANCE_WORKERS")
	var error := validate(budget_plan, state)
	if not error.is_empty():
		return _fail(error)
	if bool(budget_plan.refinement_required):
		return _fail("CPU_BUDGET_REFINEMENT_REQUIRED")
	var pending := int(budget_plan.debt_ticks)
	var allowed := int(budget_plan.allowed_ticks)
	if pending == 0 or allowed == 0:
		return {
			"success": true,
			"state": state.duplicate(true),
			"deferred": pending > 0,
			"replayed_ticks": 0,
			"remaining_debt_ticks": pending,
			"canonical_tick": int(state.tick),
			"scheduler_tick": int(budget_plan.target_tick),
			"estimated_spend_us": 0,
			"partial_progress": false,
		}
	# The source is never passed to the canonical step. Failure at any point
	# in this slice publishes NO intermediate state (A14.2 atomicity).
	var next := state.duplicate(true)
	for i in allowed:
		var stepped := Runtime.step_spatial_parallel_advance(
			next, options,
			int(budget_plan.fidelity_plan.tile_span_cells),
			int(budget_plan.fidelity_plan.max_members),
			max_prepare_workers, max_advance_workers)
		if not bool(stepped.get("success", false)):
			return _fail("CPU_BUDGET_REPLAY:" + String(stepped.get("error", "?")))
		next = stepped.state
	var remaining := pending - allowed
	if int(next.tick) != int(state.tick) + allowed:
		return _fail("CPU_BUDGET_FRONTIER")
	return {
		"success": true,
		"state": next,
		"deferred": false,
		"replayed_ticks": allowed,
		"remaining_debt_ticks": remaining,
		"canonical_tick": int(next.tick),
		"scheduler_tick": int(budget_plan.target_tick),
		"estimated_spend_us": int(budget_plan.estimated_spend_us),
		"partial_progress": remaining > 0,
	}


static func _build(state: Dictionary, fidelity_plan: Dictionary,
		estimated_tick_us: int, budget_us: int, max_replay_ticks: int) -> Dictionary:
	if not C.integer(estimated_tick_us, 1, MAX_ESTIMATE_US) \
			or not C.integer(budget_us, 1, MAX_BUDGET_US) \
			or not C.integer(max_replay_ticks, 1, Fidelity.MAX_CATCH_UP_TICKS):
		return {}
	if not Runtime.validate(state).is_empty():
		return {}
	if not Fidelity.validate(fidelity_plan, state.field, state.population).is_empty():
		return {}
	if int(fidelity_plan.committed_scheduler_tick) != int(state.tick):
		return {}
	var debt: int = int(fidelity_plan.debt_ticks)
	var refinement: bool = bool(fidelity_plan.refinement_required)
	var ready: bool = bool(fidelity_plan.global_commit_ready) and not refinement
	var allowed := 0
	if ready and debt > 0:
		# Integer credits guarantee an *estimated* no-overspend policy.
		var affordable: int = budget_us / estimated_tick_us
		allowed = mini(debt, mini(max_replay_ticks, affordable))
	var reason := "NO_DEBT"
	if refinement:
		reason = "REFINEMENT_REQUIRED"
	elif not ready:
		reason = "FIDELITY_NOT_DUE"
	elif debt > 0 and allowed == 0:
		reason = "BUDGET_EXHAUSTED"
	elif debt > allowed:
		reason = "BOUNDED_SLICE"
	elif debt > 0:
		reason = "REPLAY_COMPLETE"
	return {
		"schema": SCHEMA,
		"source_state_hash": Runtime.state_hash(state),
		"fidelity_plan": fidelity_plan.duplicate(true),
		"fidelity_plan_hash": C.digest(fidelity_plan),
		"committed_tick": int(state.tick),
		"target_tick": int(fidelity_plan.target_scheduler_tick),
		"debt_ticks": debt,
		"estimated_tick_us": estimated_tick_us,
		"budget_us": budget_us,
		"max_replay_ticks": max_replay_ticks,
		"allowed_ticks": allowed,
		"estimated_spend_us": allowed * estimated_tick_us,
		"remaining_debt_ticks": debt - allowed,
		"ready": ready,
		"refinement_required": refinement,
		"reason": reason,
	}


static func _fail(error: String) -> Dictionary:
	return {"success": false, "error": error}
