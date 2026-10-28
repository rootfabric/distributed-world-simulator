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

var passed := 0
var failed := 0

func _init() -> void:
	_post_event_paid_tick_keeps_root_cost()
	print("EVO_ARCH2_A5_RM28 assertions=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _check(value: bool, name: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		push_error("FAIL:" + name)

func _genome() -> Dictionary:
	var start := P.rule("start", [P.action("differentiate", "reproductive", [0, 10, 0], 1), P.action("retire")], "start")
	return G.create({"schema": P.SCHEMA, "entry": "start", "max_age": 8, "max_depth": 1, "rules": [start]}, "RM-A5-28 post-event root maintenance witness")

func _policy() -> Dictionary:
	var policy := LH.create_default()
	policy.uptake.basal_water_mg = 0
	policy.uptake.basal_nutrient_mg = 0
	policy.uptake.basal_organic_mg = 0
	policy.uptake.water_per_absorber_unit_mg = 0
	policy.uptake.nutrient_per_absorber_unit_mg = 0
	policy.uptake.organic_per_absorber_unit_mg = 0
	policy.metabolism.maintenance_water_per_module_mg = 2
	policy.metabolism.maintenance_energy_per_module_mj = 3
	policy.growth.transfer_permille = 500
	policy.growth.max_transfer = B.stock(10000)
	policy.regulation.growth_light_min = 500
	policy.reproduction.maturity_ticks = 1
	policy.reproduction.interval_ticks = 100
	policy.reproduction.required_reproductive_modules = 1
	policy.reproduction.offspring_per_event = 1
	policy.reproduction.endowment = B.stock()
	policy.reproduction.fee_energy_mj = 0
	policy.survival.starvation_limit_ticks = 1000
	return policy

func _field(owner: String, light: int) -> Dictionary:
	return Field.create(owner, 1, [0, 0, 0], 1000, 1, 1, F.stock(900000), F.stock(1000000), F.signals(light, 500, 0, 0))

func _encoded_state_file(blueprint: Dictionary, state: Dictionary) -> String:
	return C.encode({"schema": "dws.ecology.life-state-file.v1", "blueprint": blueprint, "state": state, "state_hash": C.digest(state)})

func _post_event_paid_tick_keeps_root_cost() -> void:
	var blueprint := BP.create(_genome(), _policy())
	_check(not blueprint.is_empty(), "blueprint_valid")
	var entry := R.individual(blueprint, "rm28.parent", [500, 0, 500], B.stock(100000))
	_check(not entry.is_empty(), "founder_valid")

	var rich := _field("rm28.rich", 1000)
	var first := R.step_population(rich, [entry], rich.owner_token, rich.owner_epoch, rich.revision)
	_check(first.success and first.propagules.size() == 1, "tick1_reproduction_succeeds")
	if not first.success or first.population.is_empty(): return
	var first_state: Dictionary = first.population[0].state
	_check(first_state.age_ticks == 1 and first_state.reproduction_count == 1 and first_state.development.grant_seq == 1, "tick1_history_matches_counterexample")

	var dark := _field("rm28.dark", 0)
	var second := R.step_population(dark, [first.population[0]], dark.owner_token, dark.owner_epoch, dark.revision)
	_check(second.success, "tick2_paid_growth_suppressed_succeeds")
	if not second.success or second.population.is_empty(): return
	var state: Dictionary = second.population[0].state
	_check(state.age_ticks == 2 and state.starvation_ticks == 0 and state.reproduction_count == 1 and state.development.grant_seq == 1, "tick2_is_distinct_paid_post_event_tick")
	_check(LS.validate(state, blueprint).is_empty(), "real_two_tick_state_valid")

	var metabolism: Dictionary = blueprint.life_history.metabolism
	var three_water_payments: int = 3 * int(metabolism.maintenance_water_per_module_mg)
	var three_energy_payments: int = 3 * int(metabolism.maintenance_energy_per_module_mj)
	_check(state.resource_ledger.maintenance.water_mg >= three_water_payments and state.resource_ledger.maintenance.energy_mj >= three_energy_payments, "runtime_paid_root_plus_post_event_reproductive_module")

	var forged: Dictionary = state.duplicate(true)
	var old_two_water: int = 2 * int(metabolism.maintenance_water_per_module_mg)
	var old_two_energy: int = 2 * int(metabolism.maintenance_energy_per_module_mj)
	var refund_water: int = int(forged.resource_ledger.maintenance.water_mg) - old_two_water
	var refund_energy: int = int(forged.resource_ledger.maintenance.energy_mj) - old_two_energy
	forged.resource_ledger.maintenance.water_mg = old_two_water
	forged.resource_ledger.maintenance.energy_mj = old_two_energy
	forged.metabolic_reserves.water_mg += refund_water
	forged.metabolic_reserves.energy_mj += refund_energy
	_check(refund_water > 0 and refund_energy > 0, "forge_preserves_conservation_with_real_refund")
	_check(LS.validate(forged, blueprint) == "LIFE_REPRODUCTION_MAINTENANCE", "missing_post_event_root_payment_rejected")
	_check(LS.serialize(forged, blueprint).is_empty(), "post_event_root_forge_not_serializable")
	_check(LS.deserialize(_encoded_state_file(blueprint, forged)).is_empty(), "post_event_root_forge_deserialize_rejected")