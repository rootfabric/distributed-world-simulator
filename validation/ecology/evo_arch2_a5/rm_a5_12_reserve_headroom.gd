extends SceneTree

const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const B = preload("res://scripts/research/ecology/v2/body_graph_v1.gd")
const P = preload("res://scripts/research/ecology/v2/development_program_v1.gd")
const G = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
const LH = preload("res://scripts/research/ecology/v2/life_history_program_v1.gd")
const BP = preload("res://scripts/research/ecology/v2/organism_blueprint_v1.gd")
const LS = preload("res://scripts/research/ecology/v2/organism_life_state_v1.gd")
const R = preload("res://scripts/research/ecology/v2/resource_lifecycle_runtime_v1.gd")
const F = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const Field = preload("res://scripts/research/ecology/v2/local_environment_field_v1.gd")
const Fixtures = preload("res://scripts/research/ecology/v2/body_program_fixtures_v1.gd")
const H = preload("res://scripts/research/ecology/v2/phenotype_snapshot_v1.gd")

var passed := 0
var failed := 0

func _init() -> void:
	_full_material_reserve_requests_no_material()
	_shared_material_headroom_is_deterministic()
	_full_water_reserve_requests_no_water()
	_full_energy_reserve_clips_photosynthesis()
	print("EVO_ARCH2_A5_RM12 assertions=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _check(value: bool, name: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		push_error("FAIL:" + name)

func _policy() -> Dictionary:
	var policy := LH.create_default()
	policy.metabolism.maintenance_energy_per_module_mj = 0
	policy.metabolism.maintenance_water_per_module_mg = 0
	policy.growth.transfer_permille = 0
	policy.reproduction.maturity_ticks = 1000000
	return policy

func _field(owner: String, stock: int = 900000, light: int = 0) -> Dictionary:
	return Field.create(owner, 1, [0, 0, 0], 1000, 1, 1, F.stock(stock), F.stock(1000000), F.signals(light, 500, 0, 0))

func _step(field: Dictionary, entry: Dictionary) -> Dictionary:
	return R.step_population(field, [entry], field.owner_token, field.owner_epoch, field.revision)

func _demand_amount(demands: Array, resource: String) -> int:
	for demand in demands:
		if demand.resource == resource:
			return int(demand.amount)
	return 0

func _base_entry(id: String, endowment: Dictionary) -> Dictionary:
	var blueprint := BP.create(Fixtures.make(0), _policy())
	return R.individual(blueprint, id, [500, 0, 500], endowment)

func _full_material_reserve_requests_no_material() -> void:
	var endowment := B.stock()
	endowment.material_mg = B.MAX_STOCK
	var entry := _base_entry("rm12.material.full", endowment)
	_check(not entry.is_empty(), "full_material_entry_valid")
	if entry.is_empty(): return
	var phenotype := H.compile(entry.state.development, entry.blueprint.genome)
	var demands := R._demands(entry.state, entry.blueprint, phenotype)
	_check(_demand_amount(demands, "nutrient_mg") == 0 and _demand_amount(demands, "organic_mg") == 0, "full_material_zero_shared_demands")
	var field := _field("rm12.material.full.field", 900000, 0)
	var result := _step(field, entry)
	_check(result.success, "full_material_step_success")
	if not result.success: return
	var state: Dictionary = result.population[0].state
	_check(result.field.ledger.outputs.nutrient_mg == 0 and result.field.ledger.outputs.organic_mg == 0, "full_material_zero_shared_grants")
	_check(state.metabolic_reserves.material_mg <= B.MAX_STOCK, "full_material_reserve_bounded")
	_check(LS.validate(state, result.population[0].blueprint).is_empty(), "full_material_conservation_valid")

func _shared_material_headroom_is_deterministic() -> void:
	var endowment := B.stock()
	endowment.material_mg = B.MAX_STOCK - 7
	var entry := _base_entry("rm12.material.seven", endowment)
	_check(not entry.is_empty(), "seven_headroom_entry_valid")
	if entry.is_empty(): return
	var phenotype := H.compile(entry.state.development, entry.blueprint.genome)
	var empty_endowment := B.stock()
	var reference := _base_entry("rm12.material.reference", empty_endowment)
	var reference_phenotype := H.compile(reference.state.development, reference.blueprint.genome)
	var desired := R._demands(reference.state, reference.blueprint, reference_phenotype)
	var desired_nutrient := _demand_amount(desired, "nutrient_mg")
	var desired_organic := _demand_amount(desired, "organic_mg")
	var demands_a := R._demands(entry.state, entry.blueprint, phenotype)
	var demands_b := R._demands(entry.state, entry.blueprint, phenotype)
	var nutrient := _demand_amount(demands_a, "nutrient_mg")
	var organic := _demand_amount(demands_a, "organic_mg")
	_check(nutrient + organic == 7, "shared_material_demands_sum_to_exact_headroom")
	var floor_nutrient := int(7 * desired_nutrient / (desired_nutrient + desired_organic))
	var floor_organic := int(7 * desired_organic / (desired_nutrient + desired_organic))
	var fixed_remainder := 7 - floor_nutrient - floor_organic
	_check(nutrient == floor_nutrient + fixed_remainder and organic == floor_organic, "shared_material_fixed_integer_remainder_rule")
	_check(C.encode(demands_a) == C.encode(demands_b), "shared_material_split_byte_deterministic")
	var field := _field("rm12.material.seven.field", 900000, 0)
	var result := _step(field, entry)
	_check(result.success, "seven_headroom_step_success")
	if not result.success: return
	var state: Dictionary = result.population[0].state
	var granted: int = int(state.resource_ledger.field_intake.nutrient_mg) + int(state.resource_ledger.field_intake.organic_mg)
	_check(granted <= 7 and granted == nutrient + organic, "shared_material_actual_grants_bounded")
	_check(state.metabolic_reserves.material_mg == B.MAX_STOCK, "shared_material_reserve_fills_without_overflow")
	_check(LS.validate(state, result.population[0].blueprint).is_empty(), "shared_material_conservation_valid")

func _full_water_reserve_requests_no_water() -> void:
	var endowment := B.stock()
	endowment.water_mg = B.MAX_STOCK
	var entry := _base_entry("rm12.water.full", endowment)
	_check(not entry.is_empty(), "full_water_entry_valid")
	if entry.is_empty(): return
	var phenotype := H.compile(entry.state.development, entry.blueprint.genome)
	var demands := R._demands(entry.state, entry.blueprint, phenotype)
	_check(_demand_amount(demands, "water_mg") == 0, "full_water_zero_demand")
	var field := _field("rm12.water.full.field", 900000, 0)
	var result := _step(field, entry)
	_check(result.success, "full_water_step_success")
	if not result.success: return
	_check(result.field.ledger.outputs.water_mg == 0, "full_water_zero_grant")
	_check(result.population[0].state.metabolic_reserves.water_mg == B.MAX_STOCK, "full_water_reserve_stays_bounded")
	_check(LS.validate(result.population[0].state, result.population[0].blueprint).is_empty(), "full_water_conservation_valid")

func _collector_policy() -> Dictionary:
	var policy := LH.create_default()
	policy.uptake.basal_water_mg = 5000
	policy.uptake.basal_nutrient_mg = 5000
	policy.uptake.basal_organic_mg = 5000
	policy.uptake.water_per_absorber_unit_mg = 0
	policy.uptake.nutrient_per_absorber_unit_mg = 0
	policy.uptake.organic_per_absorber_unit_mg = 0
	policy.metabolism.maintenance_energy_per_module_mj = 0
	policy.metabolism.maintenance_water_per_module_mg = 0
	policy.metabolism.photosynthesis_area_divisor_mm2 = 4
	policy.metabolism.photosynthesis_water_saturation_mg = 500
	policy.growth.transfer_permille = 500
	policy.growth.max_transfer = B.stock(20000)
	policy.reproduction.maturity_ticks = 1000000
	return policy

func _collector_genome() -> Dictionary:
	var leaf := P.rule("leaf", [P.action("differentiate", "collector", [0, 20, 0], 1, 6000), P.action("retire")])
	var start := P.rule("start", [P.action("differentiate", "support", [0, 10, 0], 1), P.action("branch", "support", [0, 0, 0], 0, 0, 0, "leaf")], "start")
	return G.create({"schema": P.SCHEMA, "entry": "start", "max_age": 12, "max_depth": 2, "rules": [start, leaf]}, "RM-A5-12 collector headroom witness")

func _full_energy_reserve_clips_photosynthesis() -> void:
	var blueprint := BP.create(_collector_genome(), _collector_policy())
	var entry := R.individual(blueprint, "rm12.energy.full", [500, 0, 500], B.stock(30000))
	var field := _field("rm12.energy.full.field", 900000, 1000)
	var phenotype := H.compile(entry.state.development, blueprint.genome)
	for _tick in 4:
		if int(phenotype.module_roles.get("collector", 0)) > 0:
			break
		var prepared := _step(field, entry)
		_check(prepared.success, "collector_preparation_step_success")
		if not prepared.success: return
		field = prepared.field
		entry = prepared.population[0]
		phenotype = H.compile(entry.state.development, blueprint.genome)
	_check(int(phenotype.module_roles.get("collector", 0)) > 0 and int(phenotype.statistics.get("collector_area_mm2", 0)) > 0, "collector_present_before_full_energy_step")
	var delta: int = B.MAX_STOCK - int(entry.state.metabolic_reserves.energy_mj)
	entry.state.metabolic_reserves.energy_mj += delta
	entry.state.resource_ledger.external_energy_mj += delta
	entry.state.resource_ledger.assimilated.energy_mj += delta
	_check(LS.validate(entry.state, blueprint).is_empty(), "full_energy_prestate_valid")
	var external_before: int = entry.state.resource_ledger.external_energy_mj
	var assimilated_before: int = entry.state.resource_ledger.assimilated.energy_mj
	var result := _step(field, entry)
	_check(result.success, "full_energy_strong_light_step_success")
	if not result.success: return
	var state: Dictionary = result.population[0].state
	_check(state.resource_ledger.external_energy_mj == external_before and state.resource_ledger.assimilated.energy_mj == assimilated_before, "full_energy_photosynthesis_stored_zero")
	_check(state.metabolic_reserves.energy_mj <= B.MAX_STOCK, "full_energy_reserve_bounded")
	_check(LS.validate(state, blueprint).is_empty(), "full_energy_conservation_valid")
