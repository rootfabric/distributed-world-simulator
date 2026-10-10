extends SceneTree
# ECO A14.1 measurement-only research harness. Never modifies canonical Runtime.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
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

func _initialize() -> void:
	call_deferred("_run")

func _reproductive_blueprint() -> Dictionary:
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
	return Blueprint.create(genome, policy)

func _dynamic_runtime() -> Dictionary:
	var blueprint := _reproductive_blueprint()
	
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
		"seed": 20261006, "mutation_key_prefix": "eco-a14-bench"}

func _sample(label: String, duration_us: int, canonical: Dictionary,
		replayed: int, peak_kib: int) -> void:
	var payload := {"schema": "dws.ecology.a14-1.sample.v1", "label": label,
		"wall_us": duration_us, "replayed_ticks": replayed,
		"canonical_tick": int(canonical.get("tick", -1)),
		"state_hash": C.digest(canonical),
		"static_memory_kib": peak_kib}
	print("ECO_A14_SAMPLE " + JSON.stringify(payload))

func _run() -> void:
	var initial := _dynamic_runtime()
	if initial.is_empty():
		push_error("A14_FIXTURE_FAILURE")
		quit(1)
		return
	var options := _options()
	var reference := Runtime.step_spatial_scheduled(initial, options, 4, 64)
	if not reference.success:
		push_error("A14_REFERENCE_FAILURE " + str(reference.get("error", "")))
		quit(1)
		return
	var reference_hash := C.digest(reference.state)
	for workers in [1, 2, 4, 8]:
		var start := Time.get_ticks_usec()
		var result := Runtime.step_spatial_parallel_advance(initial, options, 4, 64, workers, workers)
		var elapsed := Time.get_ticks_usec() - start
		if not result.success or C.digest(result.state) != reference_hash:
			push_error("A14_PARALLEL_MISMATCH workers=" + str(workers))
			quit(1)
			return
		_sample("parallel_advance_%d" % workers, elapsed, result.state, 1,
			int(Performance.get_monitor(Performance.MEMORY_STATIC_MAX) / 1024.0))
	var start_serial := Time.get_ticks_usec()
	var serial := Runtime.step_spatial_scheduled(initial, options, 4, 64)
	var serial_us := Time.get_ticks_usec() - start_serial
	if not serial.success or C.digest(serial.state) != reference_hash:
		push_error("A14_SERIAL_MISMATCH")
		quit(1)
		return
	_sample("spatial_serial", serial_us, serial.state, 1,
		int(Performance.get_monitor(Performance.MEMORY_STATIC_MAX) / 1024.0))
	var start_prepare := Time.get_ticks_usec()
	var prepared := Runtime.step_spatial_parallel_prepare(initial, options, 4, 64, 4)
	var prepare_us := Time.get_ticks_usec() - start_prepare
	if not prepared.success or C.digest(prepared.state) != reference_hash:
		push_error("A14_PREPARE_MISMATCH")
		quit(1)
		return
	_sample("parallel_prepare_4", prepare_us, prepared.state, 1,
		int(Performance.get_monitor(Performance.MEMORY_STATIC_MAX) / 1024.0))
	var plan_start := Time.get_ticks_usec()
	var reduced := Fidelity.create(initial.field, initial.population,
		{"tile/0000/0000": Fidelity.MODE_REDUCED}, 0, 4, 4, 4, 4, 64)
	var plan_us := Time.get_ticks_usec() - plan_start
	if reduced.is_empty():
		push_error("A14_REDUCED_PLAN_FAILURE")
		quit(1)
		return
	var validation_start := Time.get_ticks_usec()
	var error := Fidelity.validate(reduced, initial.field, initial.population)
	var validation_us := Time.get_ticks_usec() - validation_start
	if not error.is_empty():
		push_error("A14_VALIDATE_FAILURE " + error)
		quit(1)
		return
	_sample("plan_create", plan_us, initial, 0, 0)
	_sample("plan_validate", validation_us, initial, 0, 0)
	var replay_start := Time.get_ticks_usec()
	var replay := Runtime.advance_spatial_fidelity(initial, options, reduced, 4, 4)
	var replay_us := Time.get_ticks_usec() - replay_start
	if not replay.success or int(replay.replayed_ticks) != 4 or int(replay.state.tick) != 4:
		push_error("A14_REPLAY_FAILURE")
		quit(1)
		return
	var continuous := initial.duplicate(true)
	for tick in 4:
		var step := Runtime.step_spatial_parallel_advance(continuous, options, 4, 64, 4, 4)
		if not step.success:
			push_error("A14_CONTINUOUS_FAILURE " + str(tick))
			quit(1)
			return
		continuous = step.state
	if C.digest(replay.state) != C.digest(continuous):
		push_error("A14_REPLAY_HASH_MISMATCH")
		quit(1)
		return
	_sample("reduced_replay_4", replay_us, replay.state, 4,
		int(Performance.get_monitor(Performance.MEMORY_STATIC_MAX) / 1024.0))
	var defer_plan := Fidelity.create(initial.field, initial.population,
		{"tile/0000/0000": Fidelity.MODE_REDUCED}, 0, 1, 4, 4, 4, 64)
	var defer_start := Time.get_ticks_usec()
	var deferred := Runtime.advance_spatial_fidelity(initial, options, defer_plan, 4, 4)
	var defer_us := Time.get_ticks_usec() - defer_start
	if not deferred.success or not deferred.deferred or C.digest(deferred.state) != C.digest(initial):
		push_error("A14_DEFER_FAILURE")
		quit(1)
		return
	_sample("reduced_defer_1", defer_us, deferred.state, 0, 0)
	print("ECO_A14_BENCH PASS")
	quit(0)
