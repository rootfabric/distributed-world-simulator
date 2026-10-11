extends SceneTree
## ECO ARCH2 A14.3 R1: adversarial budget, starvation, exact multi-slice.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Budget = preload("res://scripts/research/ecology/v2/population_cpu_budget_wake_v1.gd")
const Priority = preload("res://scripts/research/ecology/v2/population_wake_priority_v1.gd")
const Adaptive = preload("res://scripts/research/ecology/v2/population_adaptive_fidelity_advice_v1.gd")
const Fidelity = preload("res://scripts/research/ecology/v2/population_fidelity_schedule_plan_v1.gd")
const Spatial = preload("res://scripts/research/ecology/v2/population_spatial_workset_plan_v1.gd")
const Runtime = preload("res://scripts/research/ecology/v2/ecology_runtime_v1.gd")
const Checkpoint = preload("res://scripts/research/ecology/v2/ecology_runtime_checkpoint_v1.gd")
const Lifecycle = preload("res://scripts/research/ecology/v2/resource_lifecycle_runtime_v1.gd")
const Program = preload("res://scripts/research/ecology/v2/development_program_v1.gd")
const Genome = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
const Blueprint = preload("res://scripts/research/ecology/v2/organism_blueprint_v1.gd")
const LifeHistory = preload("res://scripts/research/ecology/v2/life_history_program_v1.gd")
const FieldContract = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const Field = preload("res://scripts/research/ecology/v2/local_environment_field_v1.gd")
const Feedback = preload("res://scripts/research/ecology/v2/persistent_environmental_feedback_v1.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("A14_3_BUDGET_FAIL " + label)

func _options() -> Dictionary:
	return {"mutations_enabled": true, "operator": "module_parameter",
		"seed": 20261011, "mutation_key_prefix": "eco-a14-3-budget-r1"}

func _fixture(stable_population: bool = true) -> Dictionary:
	var program := {
		"schema": Program.SCHEMA,
		"entry": "grow",
		"max_age": 64,
		"max_depth": 1,
		"rules": [Program.rule("grow", [
			Program.action("differentiate", "collector", [0, 2, 0], 1, 10000),
			Program.action("differentiate", "absorber", [0, -2, 0], 1, 0, 100),
			Program.action("differentiate", "reproductive", [2, 0, 0], 1),
			Program.action("retire"),
		])],
	}
	var genome := Genome.create(program, "A14.3 budget canonical fixture")
	var policy := LifeHistory.create_default()
	policy.regulation.growth_light_min = 0
	policy.regulation.growth_water_min = 0
	policy.regulation.growth_competition_max = 1000
	policy.regulation.growth_temperature_min = 0
	policy.regulation.growth_temperature_max = 1000
	policy.metabolism.maintenance_energy_per_module_mj = 0
	policy.metabolism.maintenance_water_per_module_mg = 0
	policy.growth.transfer_permille = 500
	policy.reproduction.maturity_ticks = 1000 if stable_population else 2
	policy.reproduction.interval_ticks = 2
	policy.reproduction.required_reproductive_modules = 1
	policy.reproduction.offspring_per_event = 1
	policy.reproduction.endowment = {"material_mg": 100, "water_mg": 100, "energy_mj": 100}
	policy.reproduction.fee_energy_mj = 0
	var blueprint := Blueprint.create(genome, policy)
	var stock := FieldContract.stock(FieldContract.MAX_CELL_STOCK)
	var field := Field.create(
		"a14-3.budget.fixture", 1, [0, 0, 0], 1000, 8, 8,
		stock, stock, FieldContract.signals(1000, 500, 0, 0))
	if blueprint.is_empty() or field.is_empty():
		return {}
	var positions := [
		[500, 0, 500], [4500, 0, 500],
		[500, 0, 4500], [4500, 0, 4500],
	]
	var population: Array = []
	for i in positions.size():
		population.append(Lifecycle.individual(
			blueprint, "a14-3-founder-%d" % i, positions[i],
			{"material_mg": 100000, "water_mg": 100000, "energy_mj": 100000}))
	var created := Runtime.create(
		"eco/a14-3/budget-runtime/v1", field, population,
		Feedback.default_policy(), false)
	return created.state if bool(created.get("success", false)) else {}


func _run() -> void:
	var initial := _fixture()
	_check(not initial.is_empty(), "fixture exists")
	if initial.is_empty():
		_finish()
		return
	_f1_budget_and_f3_clamped_exact_replay(initial)
	_f2_starvation_and_priority(initial)
	_atomic_late_failure()
	_finish()


## F1: exhaustion holds canonical state and cannot overspend estimated credits.
## F3: replay eight owed ticks as 4 globally complete 2-tick slices; the
## canonical state after EVERY slice matches continuous at same frontier.
func _f1_budget_and_f3_clamped_exact_replay(initial: Dictionary) -> void:
	var original_bytes := C.encode(initial)
	var sleep := Adaptive.create(
		initial.field, initial.population, [], 20000, 1000, 0, 8, 4, 4, 64)
	_check(not sleep.is_empty(), "F1/F3: REDUCED plan constructed")
	if sleep.is_empty():
		return
	_check(sleep.mode == Fidelity.MODE_REDUCED
		and bool(sleep.fidelity_plan.global_commit_ready)
		and int(sleep.fidelity_plan.catch_up_ticks) == 8,
		"F3: original 8-tick debt due at cadence")

	var too_small := Budget.create(initial, sleep.fidelity_plan, 10, 9, 2)
	_check(not too_small.is_empty(), "F1: underbudget plan constructed")
	if too_small.is_empty():
		return
	_check(int(too_small.allowed_ticks) == 0
		and int(too_small.estimated_spend_us) == 0
		and too_small.reason == "BUDGET_EXHAUSTED",
		"F1: one indivisible tick cannot fit credits")
	var no_work := Budget.execute(initial, _options(), too_small, 4, 4)
	_check(bool(no_work.get("success", false))
		and bool(no_work.get("deferred", false))
		and int(no_work.get("remaining_debt_ticks", -1)) == 8,
		"F1: budget exhaustion defers all debt")
	if bool(no_work.get("success", false)):
		_check(C.encode(no_work.state) == original_bytes, "F1: defer changes no canonical byte")

	var reference := initial.duplicate(true)
	var reference_by_tick := {}
	for i in 8:
		var stepped := Runtime.step_spatial_parallel_advance(reference, _options(), 4, 64, 4, 4)
		_check(bool(stepped.get("success", false)), "F3: reference tick %d" % (i + 1))
		if not bool(stepped.get("success", false)):
			return
		reference = stepped.state
		if (i + 1) % 2 == 0:
			reference_by_tick[i + 1] = C.encode(reference)
	var cursor := initial.duplicate(true)
	for slice_index in 4:
		# Once the globally exact wake began, the remaining debt is an
		# explicit FULL continuation, even if smaller than REDUCED cadence.
		var fidelity := sleep.fidelity_plan if slice_index == 0 else Fidelity.create(
			cursor.field, cursor.population, {},
			int(cursor.tick), 8, 4, 16, 4, 64)
		_check(not fidelity.is_empty(), "F3: continuation fidelity plan")
		if fidelity.is_empty():
			return
		var plan := Budget.create(cursor, fidelity, 10, 21, 2)
		_check(not plan.is_empty(), "F3: bounded plan created")
		if plan.is_empty():
			return
		_check(Budget.validate(plan, cursor).is_empty(), "F3: plan validates")
		_check(int(plan.allowed_ticks) == 2
			and int(plan.estimated_spend_us) == 20
			and int(plan.estimated_spend_us) <= int(plan.budget_us),
			"F3: exact two-tick clamp under credits")
		var source_bytes := C.encode(cursor)
		var result := Budget.execute(cursor, _options(), plan, 4, 4)
		_check(bool(result.get("success", false)) and not bool(result.get("deferred", true))
			and int(result.get("replayed_ticks", -1)) == 2,
			"F3: slice executes exactly two whole-world ticks")
		if not bool(result.get("success", false)):
			return
		_check(C.encode(cursor) == source_bytes, "F3: slice did not mutate source")
		cursor = result.state
		_check(int(cursor.tick) == (slice_index + 1) * 2,
			"F3: canonical frontier equals slice boundary")
		_check(int(result.remaining_debt_ticks) == 8 - int(cursor.tick),
			"F3: remaining debt account exact")
		_check(C.encode(cursor) == reference_by_tick[int(cursor.tick)],
			"F3: every committed frontier byte-matches continuous")
		_check(bool(result.partial_progress) == (int(cursor.tick) < 8),
			"F3: partial flag precise")
	_check(C.encode(cursor) == C.encode(reference),
		"F3: final eight-tick exact state bytes")
	_check(Runtime.state_hash(cursor) == Runtime.state_hash(reference),
		"F3: final eight-tick state hash")
	var manifest := C.digest({"schema": "dws.ecology.a14-3-budget-fixture.v1"})
	var cp_a := Checkpoint.create(manifest, cursor)
	var cp_b := Checkpoint.create(manifest, reference)
	_check(not cp_a.is_empty() and not cp_b.is_empty(), "F3: both checkpoints valid")
	if not cp_a.is_empty() and not cp_b.is_empty():
		_check(Checkpoint.serialize(cp_a) == Checkpoint.serialize(cp_b),
			"F3: final checkpoint bytes equal continuous")
	_check(C.encode(initial) == original_bytes, "F3: source frontier untouched")

	var corrupted := too_small.duplicate(true)
	corrupted.allowed_ticks = 1
	_check(not Budget.validate(corrupted, initial).is_empty(),
		"F1: tampered execution credit quota rejected")
	_check(Budget.create(initial, sleep.fidelity_plan, 0, 21, 2).is_empty(),
		"F1: zero tick estimate rejected")
	_check(Budget.create(initial, sleep.fidelity_plan, 10, 0, 2).is_empty(),
		"F1: zero budget rejected")


## F2: noncanonical preparation grants are always deterministic; once
## an address has waited long enough it outranks a permanently active one.
## A per-address minimum cost > budget is explicitly NOT starvation-safe.
func _f2_starvation_and_priority(initial: Dictionary) -> void:
	var spatial := Spatial.create(initial.field, initial.population, 4, 64)
	_check(not spatial.is_empty(), "F2: spatial worksets")
	if spatial.is_empty():
		return
	var addresses: Array = []
	for workset in spatial.worksets:
		if not addresses.has(String(workset.address)):
			addresses.append(String(workset.address))
	addresses.sort()
	_check(addresses.size() == 4, "F2: four canonical addresses")
	if addresses.size() != 4:
		return
	var debt := {}
	var cost := {}
	var last := {}
	var granted_count := {}
	for address in addresses:
		debt[address] = 1
		cost[address] = 5
		last[address] = 0
		granted_count[address] = 0
	for epoch in range(1, 25):
		var before_last := C.encode(last)
		var queue := Priority.create(
			initial.field, initial.population, [addresses[0]],
			debt, cost, last, 5, epoch, 3, 4, 64)
		_check(not queue.is_empty(), "F2: queue epoch=%d" % epoch)
		if queue.is_empty():
			return
		_check(Priority.validate(queue, initial.field, initial.population).is_empty(),
			"F2: queue epoch=%d validates" % epoch)
		_check(C.encode(Priority.create(
			initial.field, initial.population, [addresses[0]],
			debt, cost, last, 5, epoch, 3, 4, 64)) == C.encode(queue),
			"F2: deterministic repeat epoch=%d" % epoch)
		_check(C.encode(last) == before_last, "F2: input history not mutated")
		_check(queue.selected_addresses.size() == 1
			and int(queue.spent_us) == 5 and int(queue.remaining_us) == 0,
			"F2: exactly one noncanonical preparation grant per epoch")
		var granted := String(queue.selected_addresses[0])
		granted_count[granted] = int(granted_count[granted]) + 1
		last = queue.next_last_served_epoch_by_address
		if epoch >= 8:
			for address in addresses:
				_check(epoch - int(last[address]) <= 8,
					"F2: active-heavy starvation bound address=%s epoch=%d" % [address, epoch])
	for address in addresses:
		_check(int(granted_count[address]) >= 2,
			"F2: every address receives eventual preparation service")

	var baseline := Priority.create(initial.field, initial.population,
		[addresses[0]], debt, cost, last, 5, 25, 3, 4, 64)
	_check(not baseline.is_empty(), "F2: final baseline")
	if baseline.is_empty():
		return
	var tampered := baseline.duplicate(true)
	tampered.selected_addresses = []
	_check(not Priority.validate(tampered, initial.field, initial.population).is_empty(),
		"F2: forged grants rejected")
	_check(Priority.create(initial.field, initial.population,
		[addresses[0], addresses[0]], debt, cost, last, 5, 25, 3, 4, 64).is_empty(),
		"F2: duplicate active address rejected")
	var unknown := cost.duplicate(true)
	unknown["tile/9999/9999"] = 1
	_check(Priority.create(initial.field, initial.population,
		[], debt, unknown, last, 5, 25, 3, 4, 64).is_empty(),
		"F2: unknown cost address rejected")


## Slice atomicity: a natural bounded-population failure after a successful
## local replay tick publishes no intermediate state in a failed slice.
func _atomic_late_failure() -> void:
	var cursor := _fixture(false)
	_check(not cursor.is_empty(), "R1 atomic: reproductive fixture")
	if cursor.is_empty():
		return
	var previous: Dictionary = {}
	var origin: Dictionary = {}
	var causal_error := ""
	for tick in 32:
		var stepped := Runtime.step_spatial_parallel_advance(cursor, _options(), 4, 64, 4, 4)
		if not bool(stepped.get("success", false)):
			if not previous.is_empty():
				origin = previous
				causal_error = String(stepped.get("error", ""))
			break
		previous = cursor
		cursor = stepped.state
	_check(not origin.is_empty() and not causal_error.is_empty(),
		"R1 atomic: natural second-tick failure available")
	if origin.is_empty():
		return
	var plan := Fidelity.create(origin.field, origin.population,
		{}, int(origin.tick), int(origin.tick) + 2, 4, 16, 4, 64)
	_check(not plan.is_empty(), "R1 atomic: two-tick FULL plan")
	if plan.is_empty():
		return
	var budget := Budget.create(origin, plan, 10, 21, 2)
	_check(not budget.is_empty() and int(budget.allowed_ticks) == 2,
		"R1 atomic: two steps admitted under estimated credits")
	if budget.is_empty():
		return
	var before := C.encode(origin)
	var failed := Budget.execute(origin, _options(), budget, 4, 4)
	_check(not bool(failed.get("success", false))
		and String(failed.get("error", "")) == "CPU_BUDGET_REPLAY:" + causal_error,
		"R1 atomic: failure propagated from second tick")
	_check(not failed.has("state") and not failed.has("canonical_tick"),
		"R1 atomic: no intermediate canonical state published")
	_check(C.encode(origin) == before, "R1 atomic: source untouched")


func _finish() -> void:
	print("ECO_ARCH2_A14_3_BUDGET checks=%d failed=%d" % [checks, failures])
	print("ECO_ARCH2_A14_3_BUDGET " + ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
