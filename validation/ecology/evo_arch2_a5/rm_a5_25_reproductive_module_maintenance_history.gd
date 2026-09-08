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
	_reproductive_modules_raise_historical_maintenance_floor()
	print("EVO_ARCH2_A5_RM25 assertions=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _check(value: bool, name: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		push_error("FAIL:" + name)

func _genome() -> Dictionary:
	var leaf := P.rule("leaf", [P.action("differentiate", "collector", [0, 20, 0], 1, 6000), P.action("retire")])
	var start := P.rule("start", [P.action("differentiate", "reproductive", [0, 10, 0], 1), P.action("branch", "support", [0, 0, 0], 0, 0, 0, "leaf")], "start")
	return G.create({"schema": P.SCHEMA, "entry": "start", "max_age": 32, "max_depth": 2, "rules": [start, leaf]}, "RM-A5-25 module maintenance history witness")

func _policy() -> Dictionary:
	var policy := LH.create_default()
	policy.uptake.basal_water_mg = 5000
	policy.uptake.basal_nutrient_mg = 5000
	policy.uptake.basal_organic_mg = 5000
	policy.uptake.water_per_absorber_unit_mg = 0
	policy.uptake.nutrient_per_absorber_unit_mg = 0
	policy.uptake.organic_per_absorber_unit_mg = 0
	policy.metabolism.maintenance_water_per_module_mg = 2
	policy.metabolism.maintenance_energy_per_module_mj = 3
	policy.metabolism.photosynthesis_area_divisor_mm2 = 4
	policy.metabolism.photosynthesis_water_saturation_mg = 500
	policy.growth.transfer_permille = 500
	policy.growth.max_transfer = B.stock(20000)
	policy.survival.starvation_limit_ticks = 1000
	policy.reproduction.maturity_ticks = 2
	policy.reproduction.interval_ticks = 100
	policy.reproduction.required_reproductive_modules = 1
	policy.reproduction.offspring_per_event = 1
	policy.reproduction.endowment = B.stock()
	policy.reproduction.fee_energy_mj = 0
	return policy

func _field(owner: String) -> Dictionary:
	return Field.create(owner, 1, [0, 0, 0], 1000, 1, 1, F.stock(900000), F.stock(1000000), F.signals(1000, 500, 0, 0))

func _run_ticks(entry: Dictionary, field: Dictionary, count: int) -> Dictionary:
	var current := entry
	var current_field := field
	for _tick in count:
		var result := R.step_population(current_field, [current], current_field.owner_token, current_field.owner_epoch, current_field.revision)
		if not result.success:
			return {"success": false}
		current = result.population[0]
		current_field = result.field
	return {"success": true, "entry": current, "field": current_field}

func _encoded_state_file(blueprint: Dictionary, state: Dictionary) -> String:
	return C.encode({"schema": "dws.ecology.life-state-file.v1", "blueprint": blueprint, "state": state, "state_hash": C.digest(state)})

func _reproductive_modules_raise_historical_maintenance_floor() -> void:
	var blueprint := BP.create(_genome(), _policy())
	var entry := R.individual(blueprint, "rm25.parent", [500, 0, 500], B.stock(100000))
	var run := _run_ticks(entry, _field("rm25.field"), 8)
	_check(run.success, "runtime_witness_runs")
	if not run.success: return
	var state: Dictionary = run.entry.state
	_check(state.age_ticks == 8 and state.reproduction_count == 1, "reproduction_history_present")
	_check(state.development.grant_seq > 2, "development_continues_after_reproduction")
	_check(LS.validate(state, blueprint).is_empty(), "real_state_valid")

	var reproduction: Dictionary = blueprint.life_history.reproduction
	var metabolism: Dictionary = blueprint.life_history.metabolism
	var event_count: int = int(state.reproduction_count / reproduction.offspring_per_event)
	var paid_prefix_ticks: int = state.age_ticks - state.starvation_ticks
	var survival_paid_ticks: int = int((paid_prefix_ticks + blueprint.life_history.survival.starvation_limit_ticks - 1) / blueprint.life_history.survival.starvation_limit_ticks)
	var old_root_paid_ticks: int = maxi(event_count, maxi(survival_paid_ticks, int(state.development.grant_seq)))
	var old_water_floor: int = old_root_paid_ticks * int(metabolism.maintenance_water_per_module_mg)
	var old_energy_floor: int = old_root_paid_ticks * int(metabolism.maintenance_energy_per_module_mj)
	_check(state.resource_ledger.maintenance.water_mg > old_water_floor and state.resource_ledger.maintenance.energy_mj > old_energy_floor, "real_history_contains_nonroot_maintenance")

	var old_floor_forge: Dictionary = state.duplicate(true)
	var refund_water: int = int(old_floor_forge.resource_ledger.maintenance.water_mg) - old_water_floor
	var refund_energy: int = int(old_floor_forge.resource_ledger.maintenance.energy_mj) - old_energy_floor
	old_floor_forge.resource_ledger.maintenance.water_mg = old_water_floor
	old_floor_forge.resource_ledger.maintenance.energy_mj = old_energy_floor
	old_floor_forge.metabolic_reserves.water_mg += refund_water
	old_floor_forge.metabolic_reserves.energy_mj += refund_energy
	_check(LS.validate(old_floor_forge, blueprint) == "LIFE_REPRODUCTION_MAINTENANCE", "root_only_historical_floor_rejected")
	_check(LS.serialize(old_floor_forge, blueprint).is_empty(), "root_only_forge_not_serializable")
	_check(LS.deserialize(_encoded_state_file(blueprint, old_floor_forge)).is_empty(), "root_only_forge_deserialize_rejected")

	var last_reproduction_tick: int = state.next_reproduction_tick - reproduction.interval_ticks
	var latest_first_reproduction_tick: int = last_reproduction_tick - (event_count - 1) * reproduction.interval_ticks
	var suffix_ticks: int = maxi(0, state.age_ticks - latest_first_reproduction_tick)
	var suffix_nonstarved_ticks: int = maxi(0, suffix_ticks - state.starvation_ticks)
	var suffix_survival_paid_ticks: int = 0
	if suffix_nonstarved_ticks > 0:
		suffix_survival_paid_ticks = int((suffix_nonstarved_ticks + blueprint.life_history.survival.starvation_limit_ticks - 1) / blueprint.life_history.survival.starvation_limit_ticks)
	var suffix_development_paid_ticks: int = maxi(0, int(state.development.grant_seq) - latest_first_reproduction_tick)
	var suffix_reproduction_paid_ticks: int = maxi(0, event_count - 1)
	var post_reproduction_paid_ticks: int = maxi(suffix_reproduction_paid_ticks, maxi(suffix_survival_paid_ticks, suffix_development_paid_ticks))
	var module_payment_ticks: int = old_root_paid_ticks + post_reproduction_paid_ticks * int(reproduction.required_reproductive_modules)
	_check(module_payment_ticks > old_root_paid_ticks, "module_history_strengthens_floor")

	var exact_floor: Dictionary = state.duplicate(true)
	var exact_water_floor: int = module_payment_ticks * int(metabolism.maintenance_water_per_module_mg)
	var exact_energy_floor: int = module_payment_ticks * int(metabolism.maintenance_energy_per_module_mj)
	var exact_refund_water: int = int(exact_floor.resource_ledger.maintenance.water_mg) - exact_water_floor
	var exact_refund_energy: int = int(exact_floor.resource_ledger.maintenance.energy_mj) - exact_energy_floor
	_check(exact_refund_water >= 0 and exact_refund_energy >= 0, "conservative_floor_not_above_real_payment")
	exact_floor.resource_ledger.maintenance.water_mg = exact_water_floor
	exact_floor.resource_ledger.maintenance.energy_mj = exact_energy_floor
	exact_floor.metabolic_reserves.water_mg += exact_refund_water
	exact_floor.metabolic_reserves.energy_mj += exact_refund_energy
	_check(LS.validate(exact_floor, blueprint).is_empty(), "exact_conservative_module_floor_accepted")