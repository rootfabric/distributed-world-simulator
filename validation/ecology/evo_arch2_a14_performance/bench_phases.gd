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

func _dynamic_runtime(founder_count: int = 4) -> Dictionary:
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
	if founder_count < 1 or founder_count > Runtime.MAX_POPULATION:
		return {}
	for i in founder_count:
		var position: Array = positions[i % positions.size()]
		var individual := Lifecycle.individual(
			blueprint, "fidelity-founder-%d" % i, position,
			{"material_mg": 100000, "water_mg": 100000, "energy_mj": 100000})
		if individual.is_empty():
			return {}
		population.append(individual)
	var created := Runtime.create(
		"eco/a13/fidelity-runtime/v1", field, population,
		Feedback.default_policy(), false)
	
	return created.state if created.success else {}


func _options() -> Dictionary:
	return {"mutations_enabled": true, "operator": "module_parameter",
		"seed": 20261006, "mutation_key_prefix": "eco-a14-bench"}

func _run() -> void:
	var options := _options()
	for founders in [4, 64, 128, 256]:
		var state := _dynamic_runtime(founders)
		if state.is_empty() or state.population.size() != founders:
			push_error("A14_PHASE_FIXTURE_FAILURE " + str(founders))
			quit(1)
			return
		var baseline := Runtime.step_spatial_parallel_advance(state, options, 4, 64, 4, 4)
		if not baseline.success:
			push_error("A14_PHASE_BASELINE_FAILURE " + str(founders))
			quit(1)
			return
		var target_hash := C.digest(baseline.state)
		var start := Time.get_ticks_usec()
		var lifecycle := Runtime.step_lifecycle_spatial_parallel_advance(state, 4, 64, 4, 4)
		var lifecycle_us := Time.get_ticks_usec() - start
		if not lifecycle.success:
			push_error("A14_PHASE_LIFECYCLE_FAILURE " + str(founders))
			quit(1)
			return
		start = Time.get_ticks_usec()
		var admitted := Runtime.admit_propagules(lifecycle.state, options)
		var admission_us := Time.get_ticks_usec() - start
		if not admitted.success:
			push_error("A14_PHASE_ADMISSION_FAILURE " + str(founders))
			quit(1)
			return
		start = Time.get_ticks_usec()
		var finished := Runtime.step_feedback(admitted.state)
		var feedback_us := Time.get_ticks_usec() - start
		if not finished.success or C.digest(finished.state) != target_hash:
			push_error("A14_PHASE_COMPOSITION_MISMATCH " + str(founders))
			quit(1)
			return
		_emit_phase(founders, "lifecycle_including_global_A5", lifecycle_us, target_hash)
		_emit_phase(founders, "propagule_admission", admission_us, target_hash)
		_emit_phase(founders, "feedback_and_seal", feedback_us, target_hash)
		start = Time.get_ticks_usec()
		var validation := Runtime.validate(state)
		var validate_us := Time.get_ticks_usec() - start
		if not validation.is_empty():
			push_error("A14_PHASE_VALIDATE_FAILURE " + str(founders))
			quit(1)
			return
		_emit_phase(founders, "runtime_validate", validate_us, target_hash)
		start = Time.get_ticks_usec()
		var spatial := Spatial.create(state.field, state.population, 4, 64)
		var spatial_us := Time.get_ticks_usec() - start
		if spatial.is_empty():
			push_error("A14_PHASE_SPATIAL_FAILURE " + str(founders))
			quit(1)
			return
		_emit_phase(founders, "spatial_create", spatial_us, target_hash)
		start = Time.get_ticks_usec()
		var copied := state.duplicate(true)
		var copy_us := Time.get_ticks_usec() - start
		if C.digest(copied) != C.digest(state):
			push_error("A14_PHASE_COPY_MISMATCH " + str(founders))
			quit(1)
			return
		_emit_phase(founders, "deep_copy", copy_us, target_hash)
		start = Time.get_ticks_usec()
		var state_digest := C.digest(state)
		var digest_us := Time.get_ticks_usec() - start
		if state_digest.is_empty():
			push_error("A14_PHASE_DIGEST_FAILURE " + str(founders))
			quit(1)
			return
		_emit_phase(founders, "canonical_digest", digest_us, target_hash)
	print("ECO_A14_PHASE PASS")
	quit(0)

func _emit_phase(founders: int, label: String, duration_us: int, target_hash: String) -> void:
	print("ECO_A14_PHASE_SAMPLE " + JSON.stringify({
		"schema": "dws.ecology.a14-1.phase-sample.v1",
		"founders": founders,
		"label": label,
		"wall_us": duration_us,
		"result_state_hash": target_hash,
	}))
