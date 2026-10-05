extends SceneTree

const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Spatial = preload("res://scripts/research/ecology/v2/population_spatial_workset_plan_v1.gd")
const Activity = preload("res://scripts/research/ecology/v2/population_activity_cadence_plan_v1.gd")
const Scale = preload("res://scripts/research/ecology/v2/ecology_scale_contract_v1.gd")
const Lifecycle = preload("res://scripts/research/ecology/v2/resource_lifecycle_runtime_v1.gd")
const Runtime = preload("res://scripts/research/ecology/v2/ecology_runtime_v1.gd")
const Checkpoint = preload("res://scripts/research/ecology/v2/ecology_runtime_checkpoint_v1.gd")
const Program = preload("res://scripts/research/ecology/v2/development_program_v1.gd")
const Genome = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
const Blueprint = preload("res://scripts/research/ecology/v2/organism_blueprint_v1.gd")
const LifeHistory = preload("res://scripts/research/ecology/v2/life_history_program_v1.gd")
const FieldContract = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const Field = preload("res://scripts/research/ecology/v2/local_environment_field_v1.gd")
const Feedback = preload("res://scripts/research/ecology/v2/persistent_environmental_feedback_v1.gd")
const Session = preload("res://scripts/ecology/habitat/persistent_habitat_session_v1.gd")
const Preset = preload("res://scripts/ecology/habitat/habitat_preset_v1.gd")
const Manifest = preload("res://scripts/ecology/workbench/experiment_manifest_v1.gd")
const Protocol = preload("res://scripts/research/ecology/v2/observatory_protocol_v1.gd")

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("A13_PARALLEL_PREPARE_FAIL " + message)

func _run() -> void:
	var fixture := _population_fixture()
	check(not fixture.is_empty(), "256-founder fixture starts")
	if not fixture.is_empty():
		_parallel_a5_contract(fixture)
	var initial := _dynamic_runtime()
	check(not initial.is_empty(), "dynamic runtime starts")
	if not initial.is_empty():
		_runtime_equivalence(initial)
		_activity_composition(initial)
	print("EVO_ARCH2_A13_PARALLEL_PREPARE checks=%d failed=%d" % [checks, failures.size()])
	print("EVO_ARCH2_A13_PARALLEL_PREPARE " + ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)

func _population_manifest() -> Dictionary:
	var manifest := Preset.create(20261005, 8)
	manifest["experiment_id"] = "eco/a13/parallel-prepare-equivalence/v1"
	manifest["founders"] = [{
		"founder_id": "founder/a",
		"biological_hash": null,
		"genome": Protocol.ancestor(),
	}]
	manifest["environment"] = {
		"spatial": {
			"origin_mm": [0, 0, 0],
			"cell_size_mm": 1000,
			"width": 16,
			"depth": 16,
		},
		"zones": [{
			"id": "rich",
			"water_mg": 1000000,
			"light": 1000,
			"temperature": 500,
			"nutrient_mg": 1000000,
			"organic_mg": 1000000,
		}],
	}
	var entries: Array = []
	for index in Scale.MAX_POPULATION:
		var x := index % 16
		var z := int(index / 16)
		entries.append({
			"founder_ref": "founder/a",
			"zone_id": "rich",
			"position_mm": [x * 1000 + 500, 0, z * 1000 + 500],
		})
	manifest["placement"] = {"entries": entries}
	return manifest

func _population_fixture() -> Dictionary:
	var manifest := _population_manifest()
	check(Manifest.validate(manifest).is_empty(), "parallel fixture manifest validates")
	var session := Session.new()
	var started: Dictionary = session.start(manifest)
	check(started.success, "parallel 256-founder fixture starts")
	if not started.success:
		return {}
	var state: Dictionary = session.controller.debug_state()
	check(state.population.size() == Scale.MAX_POPULATION, "parallel fixture retains all 256 founders")
	check(Runtime.validate(state.runtime).is_empty(), "parallel fixture runtime canonical")
	return state

func _signature(result: Dictionary) -> Dictionary:
	return {
		"field_hash": String(result.get("field_hash", "")),
		"field_bytes": C.encode(result.get("field", {})),
		"population_hash": C.digest(result.get("population", [])),
		"population_bytes": C.encode(result.get("population", [])),
		"propagules_hash": C.digest(result.get("propagules", [])),
		"propagules_bytes": C.encode(result.get("propagules", [])),
	}

func _parallel_a5_contract(fixture: Dictionary) -> void:
	var field: Dictionary = fixture.field
	var population: Array = fixture.population
	var plan := Spatial.create(field, population, 4, 64)
	check(not plan.is_empty(), "parallel fixture spatial plan created")
	check(plan.worksets.size() == 16, "parallel fixture exposes sixteen independent worksets")

	var serial := Lifecycle.step_population_spatial_scheduled(
		field, population, field.owner_token, field.owner_epoch, field.revision, 4, 64)
	check(serial.success, "serial spatial A5 reference succeeds")
	if not serial.success:
		return
	var expected := _signature(serial)
	check(not String(expected.field_hash).is_empty(), "serial A5 signature non-empty")

	for worker_bound in [1, 2, 4, 8]:
		var parallel := Lifecycle.step_population_spatial_parallel_prepare(
			field, population, field.owner_token, field.owner_epoch, field.revision,
			4, 64, worker_bound)
		check(parallel.success, "parallel A5 succeeds with worker bound %d" % worker_bound)
		if not parallel.success:
			continue
		check(bool(parallel.scheduler.parallel_prepare), "parallel result identifies scheduler mode")
		check(int(parallel.scheduler.worker_bound) == worker_bound, "worker bound reported exactly")
		check(int(parallel.scheduler.peak_workers) == mini(worker_bound, plan.worksets.size()),
			"worker wave remains bounded at %d" % worker_bound)
		check(int(parallel.scheduler.threaded_worksets) == plan.worksets.size(),
			"every workset executes off the main thread")
		check(int(parallel.scheduler.workset_count) == plan.worksets.size(),
			"scheduler telemetry covers all worksets")
		check(_signature(parallel) == expected,
			"parallel prepare bound %d is byte/hash exact to serial A5" % worker_bound)

	var repeated_a := Lifecycle.step_population_spatial_parallel_prepare(
		field, population, field.owner_token, field.owner_epoch, field.revision, 4, 64, 4)
	var repeated_b := Lifecycle.step_population_spatial_parallel_prepare(
		field, population, field.owner_token, field.owner_epoch, field.revision, 4, 64, 4)
	check(repeated_a.success and repeated_b.success, "repeated parallel A5 executions succeed")
	if repeated_a.success and repeated_b.success:
		check(_signature(repeated_a) == _signature(repeated_b),
			"thread completion timing cannot change parallel A5 bytes")

	var reversed: Array = population.duplicate(true)
	reversed.reverse()
	var permuted := Lifecycle.step_population_spatial_parallel_prepare(
		field, reversed, field.owner_token, field.owner_epoch, field.revision, 4, 64, 4)
	check(permuted.success, "reversed population parallel A5 succeeds")
	if permuted.success:
		check(_signature(permuted) == expected, "population input order cannot change parallel result")

	var source_field_hash := Field.state_hash(field)
	var invalid_zero := Lifecycle.step_population_spatial_parallel_prepare(
		field, population, field.owner_token, field.owner_epoch, field.revision, 4, 64, 0)
	var invalid_high := Lifecycle.step_population_spatial_parallel_prepare(
		field, population, field.owner_token, field.owner_epoch, field.revision, 4, 64,
		Lifecycle.MAX_PARALLEL_PREPARE_WORKERS + 1)
	check(not invalid_zero.success and String(invalid_zero.error) == "A5_PARALLEL_PREPARE_WORKERS",
		"zero prepare worker bound rejected fail-closed")
	check(not invalid_high.success and String(invalid_high.error) == "A5_PARALLEL_PREPARE_WORKERS",
		"worker bound above maximum rejected fail-closed")
	check(Field.state_hash(field) == source_field_hash, "invalid parallel bounds leave source field unchanged")

	var stale := Spatial.create(field, population, 4, 64)
	var moved: Array = population.duplicate(true)
	var original: Dictionary = moved[0]
	var replacement := Lifecycle.individual(
		original.blueprint, String(original.state.individual_id), [4500, 0, 500],
		original.state.metabolic_reserves.duplicate(true))
	check(not replacement.is_empty(), "parallel stale-plan replacement valid")
	if not replacement.is_empty():
		moved[0] = replacement
		moved.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return a.state.individual_id < b.state.individual_id)
		var rejected := Lifecycle.step_population_with_spatial_plan_parallel_prepare(
			field, moved, field.owner_token, field.owner_epoch, field.revision, stale, 4)
		check(not rejected.success and String(rejected.error).begins_with("A5_SPATIAL_WORKSET_PLAN:"),
			"parallel path rejects stale spatial plan before starting work")

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
	var genome := Genome.create(program, "A13 parallel prepare reproductive fixture")
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
	check(not blueprint.is_empty(), "parallel dynamic blueprint validates")
	var stock := FieldContract.stock(FieldContract.MAX_CELL_STOCK)
	var field := Field.create(
		"a13.parallel.dynamic", 1, [0, 0, 0], 1000, 8, 8,
		stock, stock, FieldContract.signals(1000, 500, 0, 0))
	check(not field.is_empty(), "parallel dynamic field validates")
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
			blueprint, "parallel-founder-%d" % i, positions[i],
			{"material_mg": 100000, "water_mg": 100000, "energy_mj": 100000})
		check(not individual.is_empty(), "parallel dynamic founder %d valid" % i)
		population.append(individual)
	var created := Runtime.create(
		"eco/a13/parallel-runtime/v1", field, population,
		Feedback.default_policy(), false)
	check(created.success, "parallel dynamic runtime canonical")
	return created.state if created.success else {}

func _options() -> Dictionary:
	return {
		"mutations_enabled": true,
		"operator": "module_parameter",
		"seed": 20261005,
		"mutation_key_prefix": "eco-a13-parallel-prepare-r1",
	}

func _runtime_equivalence(initial: Dictionary) -> void:
	var serial := initial.duplicate(true)
	var parallel := initial.duplicate(true)
	for tick_index in 8:
		var serial_step := Runtime.step_spatial_scheduled(serial, _options(), 4, 64)
		var parallel_step := Runtime.step_spatial_parallel_prepare(parallel, _options(), 4, 64, 4)
		check(serial_step.success and parallel_step.success,
			"serial/parallel runtime tick %d succeeds" % (tick_index + 1))
		if not serial_step.success or not parallel_step.success:
			return
		serial = serial_step.state
		parallel = parallel_step.state
		check(Runtime.state_hash(parallel) == Runtime.state_hash(serial),
			"parallel runtime hash exact at tick %d" % (tick_index + 1))
		check(C.encode(parallel) == C.encode(serial),
			"parallel runtime bytes exact at tick %d" % (tick_index + 1))

	check(parallel.population.size() > initial.population.size(),
		"parallel runtime includes real reproduction and mutation")

	var manifest_hash := C.digest({
		"schema": "dws.ecology.a13-parallel-prepare-fixture.v1",
		"seed": 20261005,
	})
	var cp_serial := Checkpoint.create(manifest_hash, serial)
	var cp_parallel := Checkpoint.create(manifest_hash, parallel)
	check(not cp_serial.is_empty() and not cp_parallel.is_empty(), "parallel checkpoints canonical")
	check(Checkpoint.serialize(cp_serial) == Checkpoint.serialize(cp_parallel),
		"parallel prepare scheduler metadata absent from checkpoint bytes")
	check(not C.encode(parallel).contains("parallel_prepare"),
		"parallel prepare metadata absent from canonical Runtime state")

	var before_hash := Runtime.state_hash(initial)
	var invalid := Runtime.step_spatial_parallel_prepare(initial, _options(), 4, 64, 0)
	check(not invalid.success and String(invalid.error) == "RUNTIME_LIFECYCLE:A5_PARALLEL_PREPARE_WORKERS",
		"runtime rejects invalid prepare worker bound")
	check(Runtime.state_hash(initial) == before_hash, "invalid runtime parallel tick leaves source state unchanged")

func _activity_composition(initial: Dictionary) -> void:
	var active := ["tile/0000/0000"]
	var defer_plan := Activity.create(initial.field, initial.population, active, 0, 1, 4, 4, 64)
	check(not defer_plan.is_empty(), "parallel activity defer plan created")
	var deferred := Runtime.advance_spatial_activity_cadence_parallel_prepare(
		initial, _options(), defer_plan, 4)
	check(deferred.success and bool(deferred.deferred), "parallel activity path defers before cadence")
	check(C.encode(deferred.state) == C.encode(initial), "parallel deferred activity mutates zero canonical bytes")

	var wake_plan := Activity.create(initial.field, initial.population, active, 0, 4, 4, 4, 64)
	check(not wake_plan.is_empty(), "parallel activity wake plan created")
	var serial_wake := Runtime.advance_spatial_activity_cadence(initial, _options(), wake_plan)
	var parallel_wake := Runtime.advance_spatial_activity_cadence_parallel_prepare(
		initial, _options(), wake_plan, 4)
	check(serial_wake.success and parallel_wake.success, "serial/parallel activity wake succeeds")
	if serial_wake.success and parallel_wake.success:
		check(int(parallel_wake.replayed_ticks) == 4, "parallel activity wake replays exact debt")
		check(Runtime.state_hash(parallel_wake.state) == Runtime.state_hash(serial_wake.state),
			"parallel activity catch-up hash exact to serial catch-up")
		check(C.encode(parallel_wake.state) == C.encode(serial_wake.state),
			"parallel activity catch-up bytes exact to serial catch-up")

	var invalid := Runtime.advance_spatial_activity_cadence_parallel_prepare(
		initial, _options(), defer_plan, 0)
	check(not invalid.success and String(invalid.error) == "RUNTIME_PARALLEL_PREPARE_WORKERS",
		"activity composition rejects invalid worker bound before scheduling")
