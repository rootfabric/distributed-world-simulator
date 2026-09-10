extends SceneTree

const B = preload("res://scripts/research/ecology/v2/body_graph_v1.gd")
const G = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
const LH = preload("res://scripts/research/ecology/v2/life_history_program_v1.gd")
const BP = preload("res://scripts/research/ecology/v2/organism_blueprint_v1.gd")
const LS = preload("res://scripts/research/ecology/v2/organism_life_state_v1.gd")
const R = preload("res://scripts/research/ecology/v2/resource_lifecycle_runtime_v1.gd")
const F = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const Field = preload("res://scripts/research/ecology/v2/local_environment_field_v1.gd")
const Fixtures = preload("res://scripts/research/ecology/v2/body_program_fixtures_v1.gd")

var passed := 0
var failed := 0

func _init() -> void:
	_headroom_clips_without_lifecycle_failure()
	_partial_headroom_is_exact()
	print("EVO_ARCH2_A5_RM11 assertions=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _check(value: bool, name: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		push_error("FAIL:" + name)

func _policy() -> Dictionary:
	var policy := LH.create_default()
	policy.uptake.basal_water_mg = 0
	policy.uptake.basal_nutrient_mg = 5000
	policy.uptake.basal_organic_mg = 5000
	policy.uptake.water_per_absorber_unit_mg = 0
	policy.uptake.nutrient_per_absorber_unit_mg = 0
	policy.uptake.organic_per_absorber_unit_mg = 0
	policy.regulation.growth_light_min = 0
	policy.regulation.growth_water_min = 0
	policy.regulation.growth_competition_max = 1000
	policy.regulation.growth_temperature_min = 0
	policy.regulation.growth_temperature_max = 1000
	policy.metabolism.maintenance_energy_per_module_mj = 0
	policy.metabolism.maintenance_water_per_module_mg = 0
	policy.growth.transfer_permille = 1000
	policy.growth.max_transfer = B.stock(B.MAX_STOCK)
	policy.reproduction.maturity_ticks = LS.MAX_AGE_TICK
	return policy

func _setup_field() -> Dictionary:
	var stocks := {"water_mg": F.MAX_CELL_STOCK, "nutrient_mg": 0, "organic_mg": 0}
	return Field.create("rm11.setup", 1, [0, 0, 0], 1000, 1, 1, stocks, F.stock(F.MAX_CELL_STOCK), F.signals(1000, 500, 0, 0))

func _saturated_entry() -> Dictionary:
	var blueprint := BP.create(Fixtures.make(5), _policy())
	var endowment := B.stock()
	endowment.material_mg = B.MAX_STOCK
	var entry := R.individual(blueprint, "rm11.saturated", [500, 0, 500], endowment)
	if entry.is_empty():
		return {}
	var setup_field := _setup_field()
	var setup := R.step_population(setup_field, [entry], setup_field.owner_token, setup_field.owner_epoch, setup_field.revision)
	if not setup.success:
		return {}
	var saturated: Dictionary = setup.population[0]
	if saturated.state.development.received.material_mg != B.MAX_STOCK:
		return {}
	return saturated if LS.validate(saturated.state, blueprint).is_empty() else {}

func _field() -> Dictionary:
	return Field.create("rm11.field", 1, [0, 0, 0], 1000, 1, 1, F.stock(900000), F.stock(1000000), F.signals(900, 500, 0, 0))

func _headroom_clips_without_lifecycle_failure() -> void:
	var entry := _saturated_entry()
	_check(not entry.is_empty(), "saturated_a2_state_valid")
	if entry.is_empty():
		return
	var field := _field()
	var result := R.step_population(field, [entry], field.owner_token, field.owner_epoch, field.revision)
	_check(result.success, "saturated_a2_population_step_does_not_overflow:" + String(result.get("error", "")))
	if not result.success:
		return
	var state: Dictionary = result.population[0].state
	_check(state.development.received.material_mg == B.MAX_STOCK, "a2_material_received_stays_bounded")
	_check(state.resource_ledger.growth_transferred.material_mg == B.MAX_STOCK, "unaccepted_material_not_debited_as_growth")
	_check(state.metabolic_reserves.material_mg > 0, "unaccepted_material_remains_metabolic")
	_check(LS.validate(state, result.population[0].blueprint).is_empty(), "post_boundary_lifecycle_state_valid")

func _partial_headroom_is_exact() -> void:
	var policy := _policy()
	var reserves := B.stock()
	reserves.material_mg = 100000
	var blueprint := BP.create(Fixtures.make(5), policy)
	var entry := R.individual(blueprint, "rm11.partial", [500, 0, 500], B.stock())
	_check(not entry.is_empty(), "partial_headroom_base_valid")
	if entry.is_empty():
		return
	entry.state.development.received.material_mg = B.MAX_STOCK - 7
	entry.state.development.reserves.material_mg = B.MAX_STOCK - 7
	var grant := R._growth_grant(reserves, policy, 1000, entry.state.development)
	_check(grant.material_mg == 7, "growth_grant_clipped_to_exact_a2_headroom")
	_check(grant.water_mg == 0 and grant.energy_mj == 0, "unrequested_resources_remain_zero")
