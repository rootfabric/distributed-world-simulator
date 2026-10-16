extends RefCounted
## ECO A14.4: host-side measured exact replay of complete global A5 ticks.
## Time measurements are noncanonical and never enter RNG, truth or checkpoints.
## The measured wall time is NOT a strict execution deadline: one global A5
## tick is indivisible until a separate safe causal decomposition is proven.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const F = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const Runtime = preload("res://scripts/research/ecology/v2/ecology_runtime_v1.gd")
const Fidelity = preload("res://scripts/research/ecology/v2/population_fidelity_schedule_plan_v1.gd")
const Budget = preload("res://scripts/research/ecology/v2/population_cpu_budget_wake_v1.gd")

const DEFAULT_BUDGET_US := 30000
const DEFAULT_ESTIMATE_US := 10000
const DEFAULT_MAX_TICKS := 2
const DEFAULT_TILE_SPAN_CELLS := 4
const DEFAULT_MAX_MEMBERS := 64

static func advance(state: Dictionary, options: Dictionary, target_tick: int,
		budget_us: int, estimate_tick_us: int, max_replay_ticks: int = DEFAULT_MAX_TICKS,
		tile_span_cells: int = DEFAULT_TILE_SPAN_CELLS,
		max_members: int = DEFAULT_MAX_MEMBERS,
		prepare_workers: int = 4, advance_workers: int = 4) -> Dictionary:
	var started_us: int = Time.get_ticks_usec()
	if not Runtime.validate(state).is_empty():
		return _fail("A14_4_RUNTIME_INVALID")
	var source_tick: int = int(state.tick)
	if not C.integer(target_tick, source_tick, F.MAX_TICK):
		return _fail("A14_4_TARGET_TICK")
	if target_tick - source_tick > Fidelity.MAX_CATCH_UP_TICKS:
		return _fail("A14_4_UNBOUNDED_DEBT")
	if not C.integer(budget_us, 1, Budget.MAX_BUDGET_US) \
			or not C.integer(estimate_tick_us, 1, Budget.MAX_ESTIMATE_US) \
			or not C.integer(max_replay_ticks, 1, Fidelity.MAX_CATCH_UP_TICKS):
		return _fail("A14_4_COST_INPUTS")
	# All-FULL continuation: a REDUCED partial wake MUST NOT strand its
	# remaining debt when it falls below the original reduced cadence.
	var fidelity: Dictionary = Fidelity.create(
		state.field, state.population, {}, source_tick, target_tick,
		Fidelity.DEFAULT_REDUCED_CADENCE_TICKS,
		Fidelity.DEFAULT_PATCH_CADENCE_TICKS,
		tile_span_cells, max_members)
	if fidelity.is_empty() or int(fidelity.reduced_tile_count) != 0 \
			or int(fidelity.patch_tile_count) != 0:
		return _fail("A14_4_FULL_PLAN_REQUIRED")
	var plan: Dictionary = Budget.create(
		state, fidelity, estimate_tick_us, budget_us, max_replay_ticks)
	if plan.is_empty():
		return _fail("A14_4_BUDGET_PLAN")
	var execute_started_us: int = Time.get_ticks_usec()
	var executed: Dictionary = Budget.execute(
		state, options, plan, prepare_workers, advance_workers)
	var ended_us: int = Time.get_ticks_usec()
	if not bool(executed.get("success", false)):
		return _fail("A14_4_EXECUTE:" + String(executed.get("error", "?")))
	if not executed.has("state") or not executed.state is Dictionary:
		return _fail("A14_4_RESULT_STATE")
	var ticks: int = int(executed.get("replayed_ticks", -1))
	if ticks < 0 or int(executed.state.tick) != source_tick + ticks:
		return _fail("A14_4_RESULT_FRONTIER")
	var wall_us: int = maxi(0, ended_us - started_us)
	return {
		"success": true,
		"state": executed.state,
		"source_tick": source_tick,
		"target_tick": target_tick,
		"canonical_tick": int(executed.state.tick),
		"replayed_ticks": ticks,
		"remaining_debt_ticks": target_tick - int(executed.state.tick),
		"budget_us": budget_us,
		"estimate_tick_us": estimate_tick_us,
		"estimated_spend_us": int(plan.estimated_spend_us),
		"planning_wall_us": maxi(0, execute_started_us - started_us),
		"execution_wall_us": maxi(0, ended_us - execute_started_us),
		"total_wall_us": wall_us,
		"overrun_us": maxi(0, wall_us - budget_us),
		"source_hash": Runtime.state_hash(state),
		"canonical_hash": Runtime.state_hash(executed.state),
		"deferred": bool(executed.deferred),
		"partial_progress": int(executed.get("remaining_debt_ticks", 0)) > 0,
		"reason": String(plan.reason),
	}

static func _fail(error: String) -> Dictionary:
	return {"success": false, "error": error}
