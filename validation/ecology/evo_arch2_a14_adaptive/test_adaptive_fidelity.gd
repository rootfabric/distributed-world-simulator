extends SceneTree
## A14.2 R1 adversarial exact compatibility regression.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Adaptive = preload("res://scripts/research/ecology/v2/population_adaptive_fidelity_advice_v1.gd")
const Fidelity = preload("res://scripts/research/ecology/v2/population_fidelity_schedule_plan_v1.gd")
const Spatial = preload("res://scripts/research/ecology/v2/population_spatial_workset_plan_v1.gd")
const Lifecycle = preload("res://scripts/research/ecology/v2/resource_lifecycle_runtime_v1.gd")
const Runtime = preload("res://scripts/research/ecology/v2/ecology_runtime_v1.gd")
const Program = preload("res://scripts/research/ecology/v2/development_program_v1.gd")
const Genome = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
const Blueprint = preload("res://scripts/research/ecology/v2/organism_blueprint_v1.gd")
const LifeHistory = preload("res://scripts/research/ecology/v2/life_history_program_v1.gd")
const FieldContract = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const Field = preload("res://scripts/research/ecology/v2/local_environment_field_v1.gd")
const Feedback = preload("res://scripts/research/ecology/v2/persistent_environmental_feedback_v1.gd")

var checks := 0
var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error("A14_ADAPTIVE_FAIL " + label)

func _reproductive_blueprint(stable_population: bool = false) -> Dictionary:
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
	var genome := Genome.create(program, "A13 fidelity scheduling reproductive fixture")
	var policy := LifeHistory.create_default()
	policy.regulation.growth_light_min = 0
	policy.regulation.growth_water_min = 0
	policy.regulation.growth_competition_max = 1000
	policy.regulation.growth_temperature_min = 0
	policy.regulation.growth_temperature_max = 1000
	policy.metabolism.maintenance_energy_per_module_mj = 0
	policy.metabolism.maintenance_water_per_module_mg = 0
	policy.growth.transfer_permille = 500
	policy.reproduction.maturity_ticks = 2
	policy.reproduction.interval_ticks = 2
	policy.reproduction.required_reproductive_modules = 1
	policy.reproduction.offspring_per_event = 1
	policy.reproduction.endowment = {"material_mg": 100, "water_mg": 100, "energy_mj": 100}
	policy.reproduction.fee_energy_mj = 0
	if stable_population:
		# Large-debt equivalence needs a stable canonical fixture: the
		# reproductive fixture hits RUNTIME_POPULATION_LIMIT after ~14 ticks
		# (exponential growth). Reproduction simply never matures here.
		policy.reproduction.maturity_ticks = 1000
	return Blueprint.create(genome, policy)

func _dynamic_runtime(stable_population: bool = false) -> Dictionary:
	var blueprint := _reproductive_blueprint(stable_population)
	var stock := FieldContract.stock(FieldContract.MAX_CELL_STOCK)
	var field := Field.create(
		"a13.fidelity.dynamic", 1, [0, 0, 0], 1000, 8, 8,
		stock, stock, FieldContract.signals(1000, 500, 0, 0))
	if blueprint.is_empty() or field.is_empty():
		return {}
	var positions := [
		[500, 0, 500],
		[4500, 0, 500],
		[500, 0, 4500],
		[4500, 0, 4500],
	]
	var population: Array = []
	for i in positions.size():
		var individual := Lifecycle.individual(
			blueprint, "fidelity-founder-%d" % i, positions[i],
			{"material_mg": 100000, "water_mg": 100000, "energy_mj": 100000})
		population.append(individual)
	var created := Runtime.create(
		"eco/a13/fidelity-runtime/v1", field, population,
		Feedback.default_policy(), false)
	return created.state if created.success else {}


func _options() -> Dictionary:
	return {"mutations_enabled": true, "operator": "module_parameter",
		"seed": 20261006, "mutation_key_prefix": "eco-a14-2-exact"}

func _run() -> void:
	var state := _dynamic_runtime()
	_check(not state.is_empty(), "canonical fixture")
	if state.is_empty():
		_finish()
		return
	var before := C.encode(state)
	var spatial := Spatial.create(state.field, state.population, 4, 64)
	var addresses: Array = []
	for unit in spatial.worksets:
		if not addresses.has(String(unit.address)):
			addresses.append(String(unit.address))
	addresses.sort()
	_check(addresses.size() == 4, "four occupied tiles")
	var full := Adaptive.create(state.field, state.population,
		[addresses[0]], 20000, 1000, 0, 1, 4, 4, 64)
	_check(not full.is_empty(), "active plan constructed")
	if not full.is_empty():
		_check(full.mode == Fidelity.MODE_FULL, "active tile forces globally FULL")
		_check(int(full.fidelity_plan.reduced_tile_count) == 0, "no mixed active reduced")
		_check(bool(full.fidelity_plan.global_commit_ready), "active commits immediately")
		_check(Adaptive.validate(full, state.field, state.population).is_empty(), "valid full advice")
		var progressed := Runtime.advance_spatial_fidelity(state, _options(), full.fidelity_plan, 4, 4)
		var continuous := Runtime.step_spatial_parallel_advance(state, _options(), 4, 64, 4, 4)
		_check(progressed.success and continuous.success, "full exact execution")
		if progressed.success and continuous.success:
			_check(C.encode(progressed.state) == C.encode(continuous.state), "full exact state bytes")
	var reduced := Adaptive.create(state.field, state.population, [], 20000, 1000, 0, 1, 4, 4, 64)
	_check(not reduced.is_empty(), "reduced advice constructed")
	if not reduced.is_empty():
		_check(reduced.mode == Fidelity.MODE_REDUCED, "all inactive over budget reduced")
		_check(int(reduced.fidelity_plan.reduced_tile_count) == 4, "all tiles reduced")
		var deferred := Runtime.advance_spatial_fidelity(state, _options(), reduced.fidelity_plan, 4, 4)
		_check(deferred.success and bool(deferred.deferred), "defer")
		if deferred.success:
			_check(C.encode(deferred.state) == before, "defer cannot change state")
	var wake := Adaptive.create(state.field, state.population, [], 20000, 1000, 0, 4, 4, 4, 64)
	_check(not wake.is_empty(), "wake constructed")
	if not wake.is_empty():
		var replay := Runtime.advance_spatial_fidelity(state, _options(), wake.fidelity_plan, 4, 4)
		var continuous_state := state.duplicate(true)
		var ok := true
		for i in 4:
			var stepped := Runtime.step_spatial_parallel_advance(continuous_state, _options(), 4, 64, 4, 4)
			if not stepped.success:
				ok = false
				break
			continuous_state = stepped.state
		_check(ok and replay.success, "four ticks replay")
		if ok and replay.success:
			_check(C.encode(replay.state) == C.encode(continuous_state), "wake equals continuous")
	# ---- A14.2 R1 falsifier matrix (mission section 5) ----
	# REDUCED -> exact wake for debts 2/4/16/64 must equal continuous execution.
	# The stable fixture keeps the canonical population fixed so 64 continuous
	# ticks remain within RUNTIME_POPULATION_LIMIT.
	var stable := _dynamic_runtime(true)
	_check(not stable.is_empty(), "stable debt fixture")
	var stable_before := C.encode(stable)
	for debt in [2, 4, 16, 64]:
		var wake_advice := Adaptive.create(stable.field, stable.population,
			[], 20000, 1000, 0, debt, 2, 4, 64)
		_check(not wake_advice.is_empty(), "wake debt=%d constructed" % debt)
		if wake_advice.is_empty():
			continue
		var continuous_state := stable.duplicate(true)
		var continuous_ok := true
		for i in debt:
			var stepped := Runtime.step_spatial_parallel_advance(
				continuous_state, _options(), 4, 64, 4, 4)
			if not stepped.success:
				continuous_ok = false
				break
			continuous_state = stepped.state
		_check(continuous_ok, "continuous debt=%d baseline" % debt)
		if not continuous_ok:
			continue
		var replayed := Runtime.advance_spatial_fidelity(
			stable, _options(), wake_advice.fidelity_plan, 4, 4)
		_check(replayed.success and not bool(replayed.deferred),
			"wake debt=%d exact catch-up" % debt)
		if replayed.success:
			_check(int(replayed.replayed_ticks) == debt,
				"wake debt=%d replays all ticks" % debt)
			_check(C.encode(replayed.state) == C.encode(continuous_state),
				"wake debt=%d equals continuous bytes" % debt)
		# state must remain at the pre-wake frontier: advance_spatial_fidelity
		# returns a duplicate and never mutates its input.
		_check(C.encode(stable) == stable_before, "input untouched after wake debt=%d" % debt)
		# Repeated wake on the same frontier is idempotent: identical inputs,
		# identical output bytes, canonical frontier still untouched.
		var repeat := Runtime.advance_spatial_fidelity(
			stable, _options(), wake_advice.fidelity_plan, 4, 4)
		_check(repeat.success and C.encode(repeat.state) == C.encode(replayed.state),
			"repeated wake debt=%d idempotent" % debt)
		_check(C.encode(stable) == stable_before,
			"frontier untouched after repeated wake debt=%d" % debt)
	# Cadence boundary: debt 1 < cadence 2 must defer, never partially commit.
	var boundary := Adaptive.create(state.field, state.population,
		[], 20000, 1000, 0, 1, 4, 2, 64)
	_check(not boundary.is_empty(), "boundary advice constructed")
	if not boundary.is_empty():
		_check(not bool(boundary.fidelity_plan.global_commit_ready),
			"boundary debt below cadence not ready")
		var deferred := Runtime.advance_spatial_fidelity(
			state, _options(), boundary.fidelity_plan, 4, 4)
		_check(deferred.success and bool(deferred.deferred) and int(deferred.replayed_ticks) == 0,
			"boundary defer replays nothing")
		_check(C.encode(state) == before, "boundary defer leaves state untouched")
	# Debt above the hard limit must be rejected outright.
	_check(Adaptive.create(state.field, state.population,
		[], 20000, 1000, 0, 65, 4, 2, 64).is_empty(), "debt 65 rejected")
	# PATCH must never be selected for any legal budget, and plan bytes must
	# be a pure function of inputs.
	var patch_seen := false
	for budget in [1, 999, 20000, 19999, 1000000000]:
		var advice := Adaptive.create(state.field, state.population,
			[], budget, budget, 0, 1, 4, 4, 64)
		if advice.is_empty():
			continue
		if advice.mode == Fidelity.MODE_PATCH:
			patch_seen = true
		var again := Adaptive.create(state.field, state.population,
			[], budget, budget, 0, 1, 4, 4, 64)
		_check(C.encode(advice) == C.encode(again), "advice deterministic budget=%d" % budget)
	_check(not patch_seen, "patch never auto-selected")
	# Fail-closed mid-catch-up: invalid worker parameters abort before any
	# canonical work and leave the input state byte-identical.
	var fail_plan := Adaptive.create(state.field, state.population,
		[], 20000, 1000, 0, 4, 2, 4, 64)
	if not fail_plan.is_empty():
		var aborted := Runtime.advance_spatial_fidelity(
			state, _options(), fail_plan.fidelity_plan, 0, 4)
		_check(not aborted.success, "invalid workers fail closed")
		_check(C.encode(state) == before, "aborted catch-up leaves state untouched")
	var within := Adaptive.create(state.field, state.population, [], 1000, 20000, 0, 1, 4, 4, 64)
	_check(not within.is_empty() and within.mode == Fidelity.MODE_FULL, "within budget full")
	var shuffled := Adaptive.create(state.field, state.population,
		[addresses[2], addresses[0]], 20000, 1000, 0, 1, 4, 4, 64)
	var ordered := Adaptive.create(state.field, state.population,
		[addresses[0], addresses[2]], 20000, 1000, 0, 1, 4, 4, 64)
	_check(C.encode(shuffled) == C.encode(ordered), "permutation deterministic")
	var invalid := Adaptive.create(state.field, state.population, ["tile/9999/9999"], 20000, 1000, 0, 1, 4, 4, 64)
	_check(invalid.is_empty(), "unknown activity address rejected")
	invalid = Adaptive.create(state.field, state.population, [addresses[0], addresses[0]], 20000, 1000, 0, 1, 4, 4, 64)
	_check(invalid.is_empty(), "duplicate activity address rejected")
	invalid = Adaptive.create(state.field, state.population, [], 20000, 0, 0, 1, 4, 4, 64)
	_check(invalid.is_empty(), "invalid budget rejected")
	invalid = Adaptive.create(state.field, state.population, [], 20000, 1000, 0, 65, 4, 4, 64)
	_check(invalid.is_empty(), "overflow debt rejected")
	if not reduced.is_empty():
		var tamper := reduced.duplicate(true)
		tamper.mode = Fidelity.MODE_FULL
		_check(not Adaptive.validate(tamper, state.field, state.population).is_empty(), "tamper mode rejected")
		tamper = reduced.duplicate(true)
		tamper.fidelity_plan.debt_ticks = 3
		_check(not Adaptive.validate(tamper, state.field, state.population).is_empty(), "tamper plan rejected")
		var changed: Array = state.population.duplicate(true)
		changed[0].state.position_mm = [1500, 0, 500]
		_check(not Adaptive.validate(reduced, state.field, changed).is_empty(), "stale population rejected")
	_check(C.encode(state) == before, "input state remains untouched")
	_finish()

func _finish() -> void:
	print("ECO_ARCH2_A14_2_ADAPTIVE checks=%d failed=%d" % [checks, failed])
	print("ECO_ARCH2_A14_2_ADAPTIVE " + ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)
