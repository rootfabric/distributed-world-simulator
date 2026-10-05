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
		push_error("A13_PARALLEL_ADVANCE_FAIL " + message)

func _run() -> void:
	var fixture := _population_fixture()
	check(not fixture.is_empty(), "256-founder advance fixture starts")
	if not fixture.is_empty():
		_parallel_a5_contract(fixture)
	var initial := _dynamic_runtime()
	check(not initial.is_empty(), "dynamic advance runtime starts")
	if not initial.is_empty():
		_runtime_equivalence(initial)
		_activity_composition(initial)
	print("EVO_ARCH2_A13_PARALLEL_ADVANCE checks=%d failed=%d" % [checks, failures.size()])
	print("EVO_ARCH2_A13_PARALLEL_ADVANCE " + ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)

func _population_manifest() -> Dictionary:
	var manifest := Preset.create(20261005, 8)
	manifest["experiment_id"] = "eco/a13/parallel-advance-equivalence/v1"
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
	check(Manifest.validate(manifest).is_empty(), "advance fixture manifest validates")
	var session := Session.new()
	var started: Dictionary = session.start(manifest)
	check(started.success, "advance 256-founder fixture starts")
	if not started.success:
		return {}
	var state: Dictionary = session.controller.debug_state()
	check(state.population.size() == Scale.MAX_POPULATION, "advance fixture retains all 256 founders")
	check(Runtime.validate(state.runtime).is_empty(), "advance fixture runtime canonical")
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
	check(not plan.is_empty(), "advance fixture spatial plan created")
	check(plan.worksets.size() == 16, "advance fixture exposes sixteen worksets")

	var serial := Lifecycle.step_population_spatial_scheduled(
		field, population, field.owner_token, field.owner_epoch, field.revision, 4, 64)
	var prepare_only := Lifecycle.step_population_spatial_parallel_prepare(
		field, population, field.owner_token, field.owner_epoch, field.revision, 4, 64, 4)
	check(serial.success and prepare_only.success, "serial and closed parallel-prepare references succeed")
	if not serial.success or not prepare_only.success:
		return
	var expected := _signature(serial)
	check(_signature(prepare_only) == expected, "closed parallel-prepare reference remains exact")

	for advance_bound in [1, 2, 4, 8]:
		var full := Lifecycle.step_population_spatial_parallel_advance(
			field, population, field.owner_token, field.owner_epoch, field.revision,
			4, 64, 4, advance_bound)
		check(full.success, "full parallel A5 succeeds with advance bound %d" % advance_bound)
		if not full.success:
			continue
		check(bool(full.scheduler.parallel_prepare), "full path records parallel prepare")
		check(int(full.scheduler.prepare_worker_bound) == 4, "prepare worker bound fixed for advance test")
		check(int(full.scheduler.prepare_peak_workers) == 4, "prepare peak remains bounded")
		check(int(full.scheduler.prepare_threaded_worksets) == plan.worksets.size(),
			"all preparation worksets run off main thread")
		check(bool(full.scheduler.parallel_advance), "full path records parallel advance")
		check(int(full.scheduler.advance_worker_bound) == advance_bound,
			"advance worker bound reported exactly")
		check(int(full.scheduler.advance_peak_workers) == mini(advance_bound, plan.worksets.size()),
			"advance worker wave remains bounded at %d" % advance_bound)
		check(int(full.scheduler.advance_threaded_worksets) == plan.worksets.size(),
			"every advance workset executes off main thread")
		check(int(full.scheduler.workset_count) == plan.worksets.size(),
			"full scheduler telemetry covers every workset")
		check(_signature(full) == expected,
			"full parallel bound %d byte/hash exact to serial A5" % advance_bound)
		check(_signature(full) == _signature(prepare_only),
			"parallel advance bound %d exact to closed parallel-prepare path" % advance_bound)

	var asymmetric_a := Lifecycle.step_population_spatial_parallel_advance(
		field, population, field.owner_token, field.owner_epoch, field.revision, 4, 64, 1, 8)
	var asymmetric_b := Lifecycle.step_population_spatial_parallel_advance(
		field, population, field.owner_token, field.owner_epoch, field.revision, 4, 64, 8, 1)
	check(asymmetric_a.success and asymmetric_b.success, "asymmetric prepare/advance worker bounds succeed")
	if asymmetric_a.success and asymmetric_b.success:
		check(_signature(asymmetric_a) == expected, "prepare=1 advance=8 exact")
		check(_signature(asymmetric_b) == expected, "prepare=8 advance=1 exact")

	var repeat_a := Lifecycle.step_population_spatial_parallel_advance(
		field, population, field.owner_token, field.owner_epoch, field.revision, 4, 64, 4, 4)
	var repeat_b := Lifecycle.step_population_spatial_parallel_advance(
		field, population, field.owner_token, field.owner_epoch, field.revision, 4, 64, 4, 4)
	check(repeat_a.success and repeat_b.success, "repeated full parallel A5 executions succeed")
	if repeat_a.success and repeat_b.success:
		check(_signature(repeat_a) == _signature(repeat_b),
			"thread completion timing cannot change full parallel bytes")

	var reversed: Array = population.duplicate(true)
	reversed.reverse()
	var permuted := Lifecycle.step_population_spatial_parallel_advance(
		field, reversed, field.owner_token, field.owner_epoch, field.revision, 4, 64, 4, 4)
	check(permuted.success, "reversed population full parallel A5 succeeds")
	if permuted.success:
		check(_signature(permuted) == expected, "population input order cannot change parallel advance result")

	var source_field_hash := Field.state_hash(field)
	var bad_prepare := Lifecycle.step_population_spatial_parallel_advance(
		field, population, field.owner_token, field.owner_epoch, field.revision, 4, 64, 0, 4)
	var bad_advance_zero := Lifecycle.step_population_spatial_parallel_advance(
		field, population, field.owner_token, field.owner_epoch, field.revision, 4, 64, 4, 0)
	var bad_advance_high := Lifecycle.step_population_spatial_parallel_advance(
		field, population, field.owner_token, field.owner_epoch, field.revision, 4, 64, 4,
		Lifecycle.MAX_PARALLEL_ADVANCE_WORKERS + 1)
	check(not bad_prepare.success and String(bad_prepare.error) == "A5_PARALLEL_PREPARE_WORKERS",
		"full path preserves prepare worker bound rejection")
	check(not bad_advance_zero.success and String(bad_advance_zero.error) == "A5_PARALLEL_ADVANCE_WORKERS",
		"zero advance worker bound rejected fail-closed")
	check(not bad_advance_high.success and String(bad_advance_high.error) == "A5_PARALLEL_ADVANCE_WORKERS",
		"advance worker bound above maximum rejected fail-closed")
	check(Field.state_hash(field) == source_field_hash, "invalid full parallel bounds leave source field unchanged")

	var stale := Spatial.create(field, population, 4, 64)
	var moved: Array = population.duplicate(true)
	var original: Dictionary = moved[0]
	var replacement := Lifecycle.individual(
		original.blueprint, String(original.state.individual_id), [4500, 0, 500],
		original.state.metabolic_reserves.duplicate(true))
	check(not replacement.is_empty(), "advance stale-plan replacement valid")
	if not replacement.is_empty():
		moved[0] = replacement
		moved.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return a.state.individual_id < b.state.individual_id)
		var rejected := Lifecycle.step_population_with_spatial_plan_parallel_advance(
			field, moved, field.owner_token, field.owner_epoch, field.revision,
			stale, 4, 4)
		check(not rejected.success and String(rejected.error).begins_with("A5_SPATIAL_WORKSET_PLAN:"),
			"full parallel path rejects stale spatial plan before execution")
		check(Field.state_hash(field) == source_field_hash, "stale-plan rejection leaves source field unchanged")

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
	var genome := Genome.create(program, "A13 parallel advance reproductive fixture")
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
	check(not blueprint.is_empty(), "advance dynamic blueprint validates")
	var stock := FieldContract.stock(FieldContract.MAX_CELL_STOCK)
	var field := Field.create(
		"a13.parallel.advance.dynamic", 1, [0, 0, 0], 1000, 8, 8,
		stock, stock, FieldContract.signals(1000, 500, 0, 0))
	check(not field.is_empty(), "advance dynamic field validates")
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
			blueprint, "advance-founder-%d" % i, positions[i],
			{"material_mg": 100000, "water_mg": 100000, "energy_mj": 100000})
		check(not individual.is_empty(), "advance dynamic founder %d valid" % i)
		population.append(individual)
	var created := Runtime.create(
		"eco/a13/parallel-advance-runtime/v1", field, population,
		Feedback.default_policy(), false)
	check(created.success, "advance dynamic runtime canonical")
	return created.state if created.success else {}

func _options() -> Dictionary:
	return {
		"mutations_enabled": true,
		"operator": "module_parameter",
		"seed": 20261005,
		"mutation_key_prefix": "eco-a13-parallel-advance-r1",
	}

func _runtime_equivalence(initial: Dictionary) -> void:
	var serial := initial.duplicate(true)
	var prepare_only := initial.duplicate(true)
	var full := initial.duplicate(true)
	for tick_index in 8:
		var serial_step := Runtime.step_spatial_scheduled(serial, _options(), 4, 64)
		var prepare_step := Runtime.step_spatial_parallel_prepare(
			prepare_only, _options(), 4, 64, 4)
		var full_step := Runtime.step_spatial_parallel_advance(
			full, _options(), 4, 64, 4, 4)
		check(serial_step.success and prepare_step.success and full_step.success,
			"serial/prepare/full runtime tick %d succeeds" % (tick_index + 1))
		if not serial_step.success or not prepare_step.success or not full_step.success:
			return
		serial = serial_step.state
		prepare_only = prepare_step.state
		full = full_step.state
		check(Runtime.state_hash(prepare_only) == Runtime.state_hash(serial),
			"closed parallel-prepare hash exact at tick %d" % (tick_index + 1))
		check(Runtime.state_hash(full) == Runtime.state_hash(serial),
			"parallel advance runtime hash exact at tick %d" % (tick_index + 1))
		check(C.encode(full) == C.encode(serial),
			"parallel advance runtime bytes exact at tick %d" % (tick_index + 1))
		check(C.encode(full) == C.encode(prepare_only),
			"parallel advance bytes exact to parallel-prepare at tick %d" % (tick_index + 1))

	check(full.population.size() > initial.population.size(),
		"parallel advance runtime includes real reproduction and mutation")

	var manifest_hash := C.digest({
		"schema": "dws.ecology.a13-parallel-advance-fixture.v1",
		"seed": 20261005,
	})
	var cp_serial := Checkpoint.create(manifest_hash, serial)
	var cp_prepare := Checkpoint.create(manifest_hash, prepare_only)
	var cp_full := Checkpoint.create(manifest_hash, full)
	check(not cp_serial.is_empty() and not cp_prepare.is_empty() and not cp_full.is_empty(),
		"serial/prepare/full checkpoints canonical")
	check(Checkpoint.serialize(cp_full) == Checkpoint.serialize(cp_serial),
		"parallel advance checkpoint bytes exact to serial")
	check(Checkpoint.serialize(cp_full) == Checkpoint.serialize(cp_prepare),
		"parallel advance checkpoint bytes exact to closed parallel-prepare")
	check(not C.encode(full).contains("parallel_advance"),
		"parallel advance metadata absent from canonical Runtime state")

	var before_hash := Runtime.state_hash(initial)
	var invalid := Runtime.step_spatial_parallel_advance(initial, _options(), 4, 64, 4, 0)
	check(not invalid.success and String(invalid.error) == "RUNTIME_LIFECYCLE:A5_PARALLEL_ADVANCE_WORKERS",
		"runtime rejects invalid advance worker bound")
	check(Runtime.state_hash(initial) == before_hash, "invalid advance runtime tick leaves source state unchanged")

func _activity_composition(initial: Dictionary) -> void:
	var active := ["tile/0000/0000"]
	var defer_plan := Activity.create(initial.field, initial.population, active, 0, 1, 4, 4, 64)
	check(not defer_plan.is_empty(), "advance activity defer plan created")
	var deferred := Runtime.advance_spatial_activity_cadence_parallel_advance(
		initial, _options(), defer_plan, 4, 4)
	check(deferred.success and bool(deferred.deferred), "full parallel activity path defers before cadence")
	check(C.encode(deferred.state) == C.encode(initial), "full parallel deferred activity mutates zero canonical bytes")

	var wake_plan := Activity.create(initial.field, initial.population, active, 0, 4, 4, 4, 64)
	check(not wake_plan.is_empty(), "advance activity wake plan created")
	var serial_wake := Runtime.advance_spatial_activity_cadence(initial, _options(), wake_plan)
	var prepare_wake := Runtime.advance_spatial_activity_cadence_parallel_prepare(
		initial, _options(), wake_plan, 4)
	var full_wake := Runtime.advance_spatial_activity_cadence_parallel_advance(
		initial, _options(), wake_plan, 4, 4)
	check(serial_wake.success and prepare_wake.success and full_wake.success,
		"serial/prepare/full activity wake succeeds")
	if serial_wake.success and prepare_wake.success and full_wake.success:
		check(int(full_wake.replayed_ticks) == 4, "full parallel activity wake replays exact debt")
		check(Runtime.state_hash(full_wake.state) == Runtime.state_hash(serial_wake.state),
			"full parallel activity catch-up hash exact to serial catch-up")
		check(C.encode(full_wake.state) == C.encode(serial_wake.state),
			"full parallel activity catch-up bytes exact to serial catch-up")
		check(C.encode(full_wake.state) == C.encode(prepare_wake.state),
			"full parallel activity catch-up exact to closed parallel-prepare catch-up")

	var invalid := Runtime.advance_spatial_activity_cadence_parallel_advance(
		initial, _options(), defer_plan, 4, 0)
	check(not invalid.success and String(invalid.error) == "RUNTIME_PARALLEL_ADVANCE_WORKERS",
		"activity composition rejects invalid advance worker bound before scheduling")
