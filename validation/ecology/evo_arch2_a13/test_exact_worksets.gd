extends SceneTree

const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Worksets = preload("res://scripts/research/ecology/v2/population_workset_plan_v1.gd")
const Scale = preload("res://scripts/research/ecology/v2/ecology_scale_contract_v1.gd")
const Lifecycle = preload("res://scripts/research/ecology/v2/resource_lifecycle_runtime_v1.gd")
const Runtime = preload("res://scripts/research/ecology/v2/ecology_runtime_v1.gd")
const Checkpoint = preload("res://scripts/research/ecology/v2/ecology_runtime_checkpoint_v1.gd")
const Body = preload("res://scripts/research/ecology/v2/body_graph_v1.gd")
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
		push_error("A13_WORKSET_FAIL " + message)

func _run() -> void:
	var fixture := _population_fixture(Scale.MAX_POPULATION)
	_plan_contract(fixture)
	_a5_exact_equivalence(fixture)
	_runtime_exact_equivalence()
	print("EVO_ARCH2_A13_WORKSETS checks=%d failed=%d" % [checks, failures.size()])
	print("EVO_ARCH2_A13_WORKSETS " + ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)

func _population_manifest(count: int) -> Dictionary:
	var manifest := Preset.create(20261004, 8)
	manifest["experiment_id"] = "eco/a13/workset-equivalence/v1"
	manifest["founders"] = [{
		"founder_id": "founder/a",
		"biological_hash": null,
		"genome": Protocol.ancestor(),
	}]
	manifest["environment"] = {
		"spatial": {"origin_mm": [0, 0, 0], "cell_size_mm": 1000, "width": 16, "depth": 16},
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
	for index in count:
		var x := index % 16
		var z := int(index / 16)
		entries.append({
			"founder_ref": "founder/a",
			"zone_id": "rich",
			"position_mm": [x * 1000 + 500, 0, z * 1000 + 500],
		})
	manifest["placement"] = {"entries": entries}
	return manifest

func _population_fixture(count: int) -> Dictionary:
	var manifest := _population_manifest(count)
	check(Manifest.validate(manifest).is_empty(), "A13 population fixture manifest validates")
	var session := Session.new()
	var started: Dictionary = session.start(manifest)
	check(started.success, "A13 population fixture starts")
	if not started.success:
		return {}
	var state: Dictionary = session.controller.debug_state()
	check(state.population.size() == count, "A13 fixture retains every founder")
	check(Runtime.validate(state.runtime).is_empty(), "A13 fixture runtime is canonical")
	return state

func _plan_contract(fixture: Dictionary) -> void:
	if fixture.is_empty():
		return
	var population: Array = fixture.population
	var plan64 := Worksets.create(population, 64)
	check(not plan64.is_empty(), "64-member workset plan created")
	check(Worksets.validate(plan64, population).is_empty(), "64-member plan validates")
	check(int(plan64.member_count) == Scale.MAX_POPULATION, "plan binds all 256 members")
	check(plan64.worksets.size() == 4, "256 members partition into four 64-member worksets")
	check(Worksets.member_ids(plan64).size() == Scale.MAX_POPULATION, "plan coverage contains every member exactly once")

	var plan1 := Worksets.create(population, 1)
	var plan256 := Worksets.create(population, Scale.MAX_POPULATION)
	check(plan1.worksets.size() == Scale.MAX_POPULATION, "size-1 plan creates 256 exact worksets")
	check(plan256.worksets.size() == 1, "size-256 plan creates one monolithic workset")

	var reversed := population.duplicate(true)
	reversed.reverse()
	var permuted := Worksets.create(reversed, 64)
	check(C.encode(permuted) == C.encode(plan64), "input order cannot change canonical workset plan")

	var tampered := plan64.duplicate(true)
	tampered.worksets[0].member_ids[0] = String(tampered.worksets[1].member_ids[0])
	check(not Worksets.validate(tampered, population).is_empty(), "tampered/duplicate coverage fails closed")
	check(Worksets.create(population, 0).is_empty(), "zero workset size rejected")
	check(Worksets.create(population, Scale.MAX_POPULATION + 1).is_empty(), "oversized workset rejected")

func _a5_signature(result: Dictionary) -> Dictionary:
	return {
		"field_hash": String(result.get("field_hash", "")),
		"population_hash": C.digest(result.get("population", [])),
		"propagules_hash": C.digest(result.get("propagules", [])),
	}

func _a5_exact_equivalence(fixture: Dictionary) -> void:
	if fixture.is_empty():
		return
	var field: Dictionary = fixture.field
	var population: Array = fixture.population
	var mono := Lifecycle.step_population_scheduled(
		field, population, field.owner_token, field.owner_epoch, field.revision, Scale.MAX_POPULATION)
	var work64 := Lifecycle.step_population_scheduled(
		field, population, field.owner_token, field.owner_epoch, field.revision, 64)
	var work1 := Lifecycle.step_population_scheduled(
		field, population, field.owner_token, field.owner_epoch, field.revision, 1)
	var defaulted := Lifecycle.step_population(
		field, population, field.owner_token, field.owner_epoch, field.revision)
	check(mono.success and work64.success and work1.success and defaulted.success,
		"all A5 execution partitions complete")
	if not mono.success or not work64.success or not work1.success or not defaulted.success:
		return
	var expected := _a5_signature(mono)
	var population_bytes := C.encode(mono.population)
	var propagule_bytes := C.encode(mono.propagules)
	check(not String(expected.population_hash).is_empty() and not String(expected.propagules_hash).is_empty(),
		"monolithic equivalence signatures are canonical and non-empty")
	check(not population_bytes.is_empty() and not propagule_bytes.is_empty(),
		"monolithic comparison payloads fit canonical byte bounds")
	check(_a5_signature(work64) == expected, "64-member worksets are exact-equivalent to monolithic A5")
	check(_a5_signature(work1) == expected, "size-1 worksets are exact-equivalent to monolithic A5")
	check(_a5_signature(defaulted) == expected, "default A13 workset execution is exact-equivalent")
	check(C.encode(work64.population) == population_bytes, "population bytes are identical across workset partitions")
	check(C.encode(work64.propagules) == propagule_bytes, "propagule bytes are identical across workset partitions")

	var plan := Worksets.create(population, 64)
	var tampered := plan.duplicate(true)
	tampered.worksets[0].member_ids[0] = "forged-member"
	var field_before := Field.state_hash(field)
	var population_before := C.digest(population)
	var rejected := Lifecycle.step_population_with_plan(
		field, population, field.owner_token, field.owner_epoch, field.revision, tampered)
	check(not rejected.success and String(rejected.error).begins_with("A5_WORKSET_PLAN:"),
		"tampered execution plan is rejected before lifecycle execution")
	check(Field.state_hash(field) == field_before and C.digest(population) == population_before,
		"rejected workset plan leaves source field/population unchanged")

func _reproductive_genome() -> Dictionary:
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
	return Genome.create(program, "A13 exact-workset reproductive fixture")

func _reproductive_policy() -> Dictionary:
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
	return policy

func _initial_runtime() -> Dictionary:
	var blueprint := Blueprint.create(_reproductive_genome(), _reproductive_policy())
	check(not blueprint.is_empty(), "A13 reproductive blueprint validates")
	var stock := FieldContract.stock(FieldContract.MAX_CELL_STOCK)
	var field := Field.create(
		"a13.worksets", 1, [0, 0, 0], 1000, 1, 1,
		stock, stock, FieldContract.signals(1000, 500, 0, 0))
	check(not field.is_empty(), "A13 rich field validates")
	var founder := Lifecycle.individual(
		blueprint, "a13-founder", [500, 0, 500],
		{"material_mg": 100000, "water_mg": 100000, "energy_mj": 100000})
	check(not founder.is_empty(), "A13 reproductive founder validates")
	var created := Runtime.create("eco/a13/workset-runtime/v1", field, [founder], Feedback.default_policy(), false)
	check(created.success, "A13 shared runtime starts")
	return created.state if created.success else {}

func _runtime_exact_equivalence() -> void:
	var initial := _initial_runtime()
	if initial.is_empty():
		return
	var options := {
		"mutations_enabled": true,
		"operator": "module_parameter",
		"seed": 20261004,
		"mutation_key_prefix": "eco-a13-workset-r1",
	}
	var default_state := initial.duplicate(true)
	var single_state := initial.duplicate(true)
	var mono_state := initial.duplicate(true)
	for tick_index in 8:
		var a := Runtime.step(default_state, options)
		var b := Runtime.step_scheduled(single_state, options, 1)
		var c := Runtime.step_scheduled(mono_state, options, Scale.MAX_POPULATION)
		check(a.success and b.success and c.success, "runtime workset variants complete tick %d" % tick_index)
		if not a.success or not b.success or not c.success:
			return
		default_state = a.state
		single_state = b.state
		mono_state = c.state
		check(Runtime.state_hash(default_state) == Runtime.state_hash(single_state),
			"default vs size-1 runtime hash matches at tick %d" % (tick_index + 1))
		check(Runtime.state_hash(default_state) == Runtime.state_hash(mono_state),
			"default vs monolithic runtime hash matches at tick %d" % (tick_index + 1))

	check(default_state.population.size() > 1, "dynamic equivalence fixture actually reproduces")
	var manifest_hash := C.digest({
		"schema": "dws.ecology.a13-workset-fixture.v1",
		"seed": 20261004,
		"workset_contract": Worksets.SCHEMA,
	})
	var cp_default := Checkpoint.create(manifest_hash, default_state)
	var cp_single := Checkpoint.create(manifest_hash, single_state)
	var cp_mono := Checkpoint.create(manifest_hash, mono_state)
	check(not cp_default.is_empty() and not cp_single.is_empty() and not cp_mono.is_empty(),
		"all workset variants produce canonical checkpoints")
	check(Checkpoint.serialize(cp_default) == Checkpoint.serialize(cp_single) 			and Checkpoint.serialize(cp_default) == Checkpoint.serialize(cp_mono),
		"workset size is absent from persistence and checkpoint bytes are identical")

	var before := Runtime.state_hash(default_state)
	var rejected := Runtime.step_scheduled(default_state, options, 0)
	check(not rejected.success and String(rejected.error) == "RUNTIME_LIFECYCLE:A5_WORKSET_PLAN",
		"invalid runtime workset size fails closed")
	check(Runtime.state_hash(default_state) == before, "failed scheduled tick leaves source runtime unchanged")
