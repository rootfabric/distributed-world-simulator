extends SceneTree
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const B = preload("res://scripts/research/ecology/v2/body_graph_v1.gd")
const P = preload("res://scripts/research/ecology/v2/development_program_v1.gd")
const G = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
const LH = preload("res://scripts/research/ecology/v2/life_history_program_v1.gd")
const BP = preload("res://scripts/research/ecology/v2/organism_blueprint_v1.gd")
const R = preload("res://scripts/research/ecology/v2/resource_lifecycle_runtime_v1.gd")
const F = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const Field = preload("res://scripts/research/ecology/v2/local_environment_field_v1.gd")
const Fixtures = preload("res://scripts/research/ecology/v2/body_program_fixtures_v1.gd")
const H = preload("res://scripts/research/ecology/v2/phenotype_snapshot_v1.gd")
var passed := 0
var failed := 0

func _init() -> void:
	_regulation_freezes_prepaid_a2()
	_unpaid_maintenance_blocks_reproduction()
	_propagule_endowment_bound()
	print("EVO_ARCH2_A5_REPAIRS assertions=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _check(v: bool, name: String) -> void:
	if v: passed += 1
	else: failed += 1; push_error("FAIL:" + name)

func _field(owner: String, stock: int, light: int) -> Dictionary:
	return Field.create(owner, 1, [0,0,0], 1000, 1, 1, F.stock(stock), F.stock(1000000), F.signals(light, 500, 0, 0))

func _policy() -> Dictionary:
	var p := LH.create_default()
	p.uptake.basal_water_mg = 5000; p.uptake.basal_nutrient_mg = 5000; p.uptake.basal_organic_mg = 5000
	p.uptake.water_per_absorber_unit_mg = 0; p.uptake.nutrient_per_absorber_unit_mg = 0; p.uptake.organic_per_absorber_unit_mg = 0
	p.metabolism.maintenance_energy_per_module_mj = 2; p.metabolism.maintenance_water_per_module_mg = 1
	p.metabolism.photosynthesis_area_divisor_mm2 = 4; p.metabolism.photosynthesis_water_saturation_mg = 500
	p.growth.transfer_permille = 500; p.growth.max_transfer = B.stock(20000)
	return p

func _reproductive_genome() -> Dictionary:
	var leaf := P.rule("leaf", [P.action("differentiate", "collector", [0,20,0], 1, 6000), P.action("retire")])
	var start := P.rule("start", [P.action("differentiate", "reproductive", [0,10,0], 1), P.action("branch", "support", [0,0,0], 0,0,0, "leaf")], "start")
	return G.create({"schema": P.SCHEMA, "entry": "start", "max_age": 12, "max_depth": 2, "rules": [start, leaf]}, "A5 reviewer repair witness")

func _step(field: Dictionary, population: Array) -> Dictionary:
	return R.step_population(field, population, field.owner_token, field.owner_epoch, field.revision)

func _regulation_freezes_prepaid_a2() -> void:
	var blueprint := BP.create(Fixtures.make(5), _policy())
	var entry := R.individual(blueprint, "repair.regulation", [500,0,500], B.stock(30000))
	var rich := _step(_field("repair.reg.rich", 800000, 900), [entry])
	_check(rich.success and rich.population[0].state.development.reserves.material_mg > 0, "prepaid_a2_residual_exists")
	var before := C.digest(rich.population[0].state.development)
	var dark := _step(_field("repair.reg.dark", 800000, 0), rich.population)
	_check(dark.success, "dark_step_success")
	_check(C.digest(dark.population[0].state.development) == before, "dark_gate_freezes_a2_advancement")

func _unpaid_maintenance_blocks_reproduction() -> void:
	var p := _policy()
	p.metabolism.maintenance_water_per_module_mg = 2500
	p.survival.starvation_limit_ticks = 3
	p.reproduction.maturity_ticks = 2; p.reproduction.interval_ticks = 1
	p.reproduction.endowment = B.stock(); p.reproduction.fee_energy_mj = 0
	var blueprint := BP.create(_reproductive_genome(), p)
	var parent := R.individual(blueprint, "repair.maintenance", [500,0,500], B.stock(1000))
	var prepared := _step(_field("repair.maintenance.rich", 900000, 900), [parent])
	_check(prepared.success and int(H.compile(prepared.population[0].state.development, blueprint.genome).module_roles.get("reproductive", 0)) >= 1, "reproductive_parent_prepared")
	var starved := _step(_field("repair.maintenance.starve", 0, 900), prepared.population)
	_check(starved.success and starved.population[0].state.alive and starved.population[0].state.starvation_ticks == 1, "maintenance_unpaid_but_parent_alive")
	_check(starved.propagules.is_empty() and starved.population[0].state.reproduction_count == 0, "unpaid_maintenance_no_reproduction")

func _propagule_endowment_bound() -> void:
	var blueprint := BP.create(_reproductive_genome(), _policy())
	var correct := {"schema": R.PROPAGULE_SCHEMA, "id": "seed.test", "parent_id": "parent.test", "blueprint_hash": BP.biological_hash(blueprint), "birth_tick": 1, "position_mm": [500,0,500], "endowment": blueprint.life_history.reproduction.endowment.duplicate(true), "parent_state_hash": "a".repeat(64)}
	_check(R.validate_propagule(correct, blueprint).is_empty(), "correct_endowment_valid")
	var tampered := correct.duplicate(true); tampered.endowment.material_mg += 1
	_check(R.validate_propagule(tampered, blueprint) == "PROPAGULE_ENDOWMENT" and R.materialize_propagule(tampered, blueprint).is_empty(), "tampered_endowment_rejected")
