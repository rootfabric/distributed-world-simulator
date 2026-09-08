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
	_survival_history_requires_repeated_maintenance()
	_development_history_strengthens_maintenance_bound()
	print("EVO_ARCH2_A5_RM22 assertions=%d failed=%d" % [passed, failed])
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
	return G.create({"schema": P.SCHEMA, "entry": "start", "max_age": 32, "max_depth": 2, "rules": [start, leaf]}, "RM-A5-22 maintenance causality witness")

func _policy(starvation_limit: int) -> Dictionary:
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
	policy.survival.starvation_limit_ticks = starvation_limit
	policy.reproduction.maturity_ticks = 2
	policy.reproduction.interval_ticks = 100
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

func _survival_history_requires_repeated_maintenance() -> void:
	var blueprint := BP.create(_genome(), _policy(3))
	var entry := R.individual(blueprint, "rm22.survival", [500, 0, 500], B.stock(50000))
	var run := _run_ticks(entry, _field("rm22.survival.field"), 8)
	_check(run.success, "survival_runtime_witness_runs")
	if not run.success: return
	var state: Dictionary = run.entry.state
	_check(state.age_ticks == 8 and state.starvation_ticks == 0 and state.reproduction_count == 1, "survival_history_has_one_reproduction")
	_check(LS.validate(state, blueprint).is_empty(), "survival_history_valid")
	var metabolism: Dictionary = blueprint.life_history.metabolism
	var required_paid_ticks := int((state.age_ticks + blueprint.life_history.survival.starvation_limit_ticks - 1) / blueprint.life_history.survival.starvation_limit_ticks)
	_check(required_paid_ticks > state.reproduction_count, "survival_bound_stronger_than_event_count")
	var tampered: Dictionary = state.duplicate(true)
	var keep_water := state.reproduction_count * metabolism.maintenance_water_per_module_mg
	var keep_energy := state.reproduction_count * metabolism.maintenance_energy_per_module_mj
	var refund_water := tampered.resource_ledger.maintenance.water_mg - keep_water
	var refund_energy := tampered.resource_ledger.maintenance.energy_mj - keep_energy
	tampered.resource_ledger.maintenance.water_mg = keep_water
	tampered.resource_ledger.maintenance.energy_mj = keep_energy
	tampered.metabolic_reserves.water_mg += refund_water
	tampered.metabolic_reserves.energy_mj += refund_energy
	_check(LS.validate(tampered, blueprint) == "LIFE_REPRODUCTION_MAINTENANCE", "event_count_only_maintenance_refund_rejected")
	_check(LS.serialize(tampered, blueprint).is_empty(), "event_count_only_history_not_serializable")
	_check(LS.deserialize(_encoded_state_file(blueprint, tampered)).is_empty(), "event_count_only_history_deserialize_rejected")

func _development_history_strengthens_maintenance_bound() -> void:
	var blueprint := BP.create(_genome(), _policy(1000))
	var entry := R.individual(blueprint, "rm22.development", [500, 0, 500], B.stock(50000))
	var run := _run_ticks(entry, _field("rm22.development.field"), 5)
	_check(run.success, "development_runtime_witness_runs")
	if not run.success: return
	var state: Dictionary = run.entry.state
	_check(state.development.grant_seq > 1, "development_history_proves_multiple_paid_ticks")
	_check(LS.validate(state, blueprint).is_empty(), "development_history_valid")
	var metabolism: Dictionary = blueprint.life_history.metabolism
	var tampered: Dictionary = state.duplicate(true)
	var keep_water := metabolism.maintenance_water_per_module_mg
	var keep_energy := metabolism.maintenance_energy_per_module_mj
	var refund_water := tampered.resource_ledger.maintenance.water_mg - keep_water
	var refund_energy := tampered.resource_ledger.maintenance.energy_mj - keep_energy
	tampered.resource_ledger.maintenance.water_mg = keep_water
	tampered.resource_ledger.maintenance.energy_mj = keep_energy
	tampered.metabolic_reserves.water_mg += refund_water
	tampered.metabolic_reserves.energy_mj += refund_energy
	_check(LS.validate(tampered, blueprint) == "LIFE_REPRODUCTION_MAINTENANCE", "development_proven_maintenance_refund_rejected")
	_check(LS.serialize(tampered, blueprint).is_empty(), "development_bound_tamper_not_serializable")