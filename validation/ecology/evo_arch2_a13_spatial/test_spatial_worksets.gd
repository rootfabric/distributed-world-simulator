extends SceneTree

const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Spatial = preload("res://scripts/research/ecology/v2/population_spatial_workset_plan_v1.gd")
const Exact = preload("res://scripts/research/ecology/v2/population_workset_plan_v1.gd")
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
		push_error("A13_SPATIAL_FAIL " + message)

func _run() -> void:
	var fixture := _population_fixture()
	_address_contract(fixture)
	_sharding_contract(fixture)
	_migration_contract()
	_a5_exact_equivalence(fixture)
	_runtime_exact_equivalence()
	print("EVO_ARCH2_A13_SPATIAL checks=%d failed=%d" % [checks, failures.size()])
	print("EVO_ARCH2_A13_SPATIAL " + ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)

func _population_manifest() -> Dictionary:
	var manifest := Preset.create(20261004, 8)
	manifest["experiment_id"] = "eco/a13/spatial-workset-equivalence/v1"
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
	check(Manifest.validate(manifest).is_empty(), "spatial fixture manifest validates")
	var session := Session.new()
	var started: Dictionary = session.start(manifest)
	check(started.success, "spatial 256-founder fixture starts")
	if not started.success:
		return {}
	var state: Dictionary = session.controller.debug_state()
	check(state.population.size() == Scale.MAX_POPULATION, "all 256 spatial founders retained")
	check(Runtime.validate(state.runtime).is_empty(), "spatial fixture runtime canonical")
	return state

func _address_contract(fixture: Dictionary) -> void:
	if fixture.is_empty():
		return
	var field: Dictionary = fixture.field
	var population: Array = fixture.population
	var plan := Spatial.create(field, population, 4, 64)
	check(not plan.is_empty(), "4-cell spatial plan created")
	check(Spatial.validate(plan, field, population).is_empty(), "spatial plan validates")
	check(int(plan.member_count) == 256, "spatial plan binds all 256 members")
	check(plan.worksets.size() == 16, "16x16 field with 4-cell tiles produces 16 worksets")
	check(Spatial.member_ids(plan).size() == 256, "spatial coverage contains all members")
	check(Spatial.member_address_map(plan).size() == 256, "every member has one spatial address")
	check(String(plan.worksets[0].address) == "tile/0000/0000", "first tile address canonical")
	check(String(plan.worksets[-1].address) == "tile/0003/0003", "last tile address canonical")
	for unit in plan.worksets:
		check(unit.member_ids.size() == 16, "uniform 16-member tile occupancy")

	var reversed := population.duplicate(true)
	reversed.reverse()
	var permuted := Spatial.create(field, reversed, 4, 64)
	check(C.encode(permuted) == C.encode(plan), "input permutation cannot change spatial plan")

	var exact := Exact.create(population, 64)
	check(not exact.is_empty(), "closed exact-workset contract remains available")
	var spatial_ids := Spatial.member_ids(plan)
	spatial_ids.sort()
	var exact_ids := Exact.member_ids(exact)
	exact_ids.sort()
	check(spatial_ids == exact_ids, "spatial and exact schedulers cover identical membership")

	var top_left := Spatial.address_for_position(field, [500, 0, 500], 4)
	var bottom_right := Spatial.address_for_position(field, [15500, 0, 15500], 4)
	check(String(top_left.address) == "tile/0000/0000", "top-left coordinate maps canonically")
	check(String(bottom_right.address) == "tile/0003/0003", "bottom-right coordinate maps canonically")
	check(Spatial.address_for_position(field, [-1, 0, 500], 4).is_empty(), "out-of-field coordinate rejected")

func _sharding_contract(fixture: Dictionary) -> void:
	if fixture.is_empty():
		return
	var field: Dictionary = fixture.field
	var population: Array = fixture.population
	var plan := Spatial.create(field, population, 16, 32)
	check(not plan.is_empty(), "single-tile sharded plan created")
	check(plan.worksets.size() == 8, "256 members split into eight 32-member shards")
	for i in plan.worksets.size():
		var unit: Dictionary = plan.worksets[i]
		check(String(unit.address) == "tile/0000/0000", "all shards retain same spatial address")
		check(int(unit.shard) == i, "shard indices canonical")
		check(unit.member_ids.size() == 32, "each shard respects member budget")

	var tampered := plan.duplicate(true)
	tampered.worksets[0].member_ids[0] = String(tampered.worksets[1].member_ids[0])
	check(not Spatial.validate(tampered, field, population).is_empty(), "duplicate/tampered spatial membership rejected")

	var stale_geometry := plan.duplicate(true)
	stale_geometry.field_geometry_hash = "0".repeat(64)
	check(Spatial.validate(stale_geometry, field, population) == "SPATIAL_PLAN_FIELD_GEOMETRY",
		"forged geometry binding rejected")

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
	var genome := Genome.create(program, "A13 spatial reproductive fixture")
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

func _migration_contract() -> void:
	var blueprint := _reproductive_blueprint()
	check(not blueprint.is_empty(), "migration blueprint validates")
	var stock := FieldContract.stock(FieldContract.MAX_CELL_STOCK)
	var field := Field.create(
		"a13.spatial.migration", 1, [0, 0, 0], 1000, 8, 8,
		stock, stock, FieldContract.signals(1000, 500, 0, 0))
	check(not field.is_empty(), "migration field validates")
	if blueprint.is_empty() or field.is_empty():
		return

	var a := Lifecycle.individual(blueprint, "migrant", [500, 0, 500],
		{"material_mg": 10000, "water_mg": 10000, "energy_mj": 10000})
	var b := Lifecycle.individual(blueprint, "migrant", [4500, 0, 500],
		{"material_mg": 10000, "water_mg": 10000, "energy_mj": 10000})
	var plan_a := Spatial.create(field, [a], 4, 64)
	var plan_b := Spatial.create(field, [b], 4, 64)
	check(String(plan_a.worksets[0].address) == "tile/0000/0000", "migrant initial address derived from canonical position")
	check(String(plan_b.worksets[0].address) == "tile/0000/0001", "migrant new address derived after canonical move")
	check(String(plan_a.population_hash) != String(plan_b.population_hash), "migration changes spatial projection binding")
	check(Spatial.validate(plan_a, field, [b]) == "SPATIAL_PLAN_POPULATION_HASH",
		"pre-migration plan becomes stale after move")
	check(not C.encode(a).contains("tile/") and not C.encode(b).contains("tile/"),
		"spatial scheduler address is absent from organism state")

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
	var exact := Lifecycle.step_population_scheduled(
		field, population, field.owner_token, field.owner_epoch, field.revision, 64)
	var spatial := Lifecycle.step_population_spatial_scheduled(
		field, population, field.owner_token, field.owner_epoch, field.revision, 4, 64)
	var sharded := Lifecycle.step_population_spatial_scheduled(
		field, population, field.owner_token, field.owner_epoch, field.revision, 16, 32)
	check(exact.success and spatial.success and sharded.success, "exact/spatial A5 variants complete")
	if not exact.success or not spatial.success or not sharded.success:
		return
	var expected := _a5_signature(exact)
	check(not String(expected.population_hash).is_empty(), "A5 equivalence signature non-empty")
	check(_a5_signature(spatial) == expected, "16-tile spatial execution exact-equivalent to closed scheduler")
	check(_a5_signature(sharded) == expected, "single-tile sharded execution exact-equivalent to closed scheduler")
	check(C.encode(spatial.population) == C.encode(exact.population), "spatial population bytes identical")
	check(C.encode(spatial.propagules) == C.encode(exact.propagules), "spatial propagule bytes identical")

	var stale := Spatial.create(field, population, 4, 64)
	var moved_population: Array = population.duplicate(true)
	var replacement := Lifecycle.individual(
		moved_population[0].blueprint,
		String(moved_population[0].state.individual_id),
		[4500, 0, 500],
		moved_population[0].state.metabolic_reserves.duplicate(true))
	# The replacement has a new valid founder genesis and is sufficient to
	# prove plan staleness; execution must reject before any lifecycle work.
	moved_population[0] = replacement
	moved_population.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		return x.state.individual_id < y.state.individual_id)
	var source_field_hash := Field.state_hash(field)
	var rejected := Lifecycle.step_population_with_spatial_plan(
		field, moved_population, field.owner_token, field.owner_epoch, field.revision, stale)
	check(not rejected.success and String(rejected.error).begins_with("A5_SPATIAL_WORKSET_PLAN:"),
		"stale spatial plan rejected before lifecycle execution")
	check(Field.state_hash(field) == source_field_hash, "stale-plan rejection leaves source field unchanged")

func _dynamic_runtime() -> Dictionary:
	var blueprint := _reproductive_blueprint()
	var stock := FieldContract.stock(FieldContract.MAX_CELL_STOCK)
	var field := Field.create(
		"a13.spatial.dynamic", 1, [0, 0, 0], 1000, 8, 8,
		stock, stock, FieldContract.signals(1000, 500, 0, 0))
	var positions := [
		[500, 0, 500],
		[4500, 0, 500],
		[500, 0, 4500],
		[4500, 0, 4500],
	]
	var population: Array = []
	for i in positions.size():
		population.append(Lifecycle.individual(
			blueprint, "spatial-founder-%d" % i, positions[i],
			{"material_mg": 100000, "water_mg": 100000, "energy_mj": 100000}))
	var created := Runtime.create(
		"eco/a13/spatial-runtime/v1", field, population,
		Feedback.default_policy(), false)
	check(created.success, "multi-tile dynamic runtime starts")
	return created.state if created.success else {}

func _runtime_exact_equivalence() -> void:
	var initial := _dynamic_runtime()
	if initial.is_empty():
		return
	var initial_plan := Spatial.create(initial.field, initial.population, 4, 64)
	check(initial_plan.worksets.size() == 4, "dynamic fixture begins in four spatial tiles")
	var options := {
		"mutations_enabled": true,
		"operator": "module_parameter",
		"seed": 20261004,
		"mutation_key_prefix": "eco-a13-spatial-r1",
	}
	var exact_state := initial.duplicate(true)
	var spatial_state := initial.duplicate(true)
	for tick_index in 8:
		var exact_step := Runtime.step_scheduled(exact_state, options, 64)
		var spatial_step := Runtime.step_spatial_scheduled(spatial_state, options, 4, 64)
		check(exact_step.success and spatial_step.success,
			"exact/spatial runtime complete tick %d" % tick_index)
		if not exact_step.success or not spatial_step.success:
			return
		exact_state = exact_step.state
		spatial_state = spatial_step.state
		check(Runtime.state_hash(exact_state) == Runtime.state_hash(spatial_state),
			"spatial runtime hash exact at tick %d" % (tick_index + 1))
		var current_plan := Spatial.create(spatial_state.field, spatial_state.population, 4, 64)
		check(not current_plan.is_empty(), "spatial addressing recomputed at tick %d" % (tick_index + 1))

	check(spatial_state.population.size() > 4, "multi-tile fixture actually reproduces")
	var manifest_hash := C.digest({
		"schema": "dws.ecology.a13-spatial-fixture.v1",
		"seed": 20261004,
	})
	var cp_exact := Checkpoint.create(manifest_hash, exact_state)
	var cp_spatial := Checkpoint.create(manifest_hash, spatial_state)
	check(not cp_exact.is_empty() and not cp_spatial.is_empty(), "exact/spatial checkpoints canonical")
	check(Checkpoint.serialize(cp_exact) == Checkpoint.serialize(cp_spatial),
		"spatial scheduler metadata absent from persistence bytes")

	var before := Runtime.state_hash(spatial_state)
	var rejected := Runtime.step_spatial_scheduled(spatial_state, options, 0, 64)
	check(not rejected.success and String(rejected.error) == "RUNTIME_LIFECYCLE:A5_SPATIAL_WORKSET_PLAN",
		"invalid spatial tile span fails closed")
	check(Runtime.state_hash(spatial_state) == before, "failed spatial tick leaves source runtime unchanged")
