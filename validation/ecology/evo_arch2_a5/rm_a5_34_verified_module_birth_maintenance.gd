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
	_forged_creation_marker_cannot_reduce_floor()
	_unfunded_birth_maintenance_rolls_back_candidate_growth()
	print("EVO_ARCH2_A5_RM34 assertions=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _check(value: bool, name: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		push_error("FAIL:" + name)

func _genome(delta_y: int = 10) -> Dictionary:
	var leaf := P.rule("leaf", [P.action("retire")])
	var start := P.rule("start", [
		P.action("extend", "support", [0, delta_y, 0], 1),
		P.action("branch", "support", [0, 0, 0], 0, 0, 0, "leaf"),
		P.action("retire"),
	])
	return G.create({"schema": P.SCHEMA, "entry": "start", "max_age": 32, "max_depth": 2, "rules": [start, leaf]}, "RM-A5-34 verified module birth maintenance witness")

func _policy(transfer_permille: int = 500) -> Dictionary:
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
	policy.growth.transfer_permille = transfer_permille
	policy.growth.max_transfer = B.stock(20000)
	policy.survival.starvation_limit_ticks = 100
	policy.reproduction.maturity_ticks = 100
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
			return {"success": false, "error": result.error}
		current = result.population[0]
		current_field = result.field
	return {"success": true, "entry": current, "field": current_field}

func _encoded_state_file(blueprint: Dictionary, state: Dictionary) -> String:
	return C.encode({"schema": "dws.ecology.life-state-file.v1", "blueprint": blueprint, "state": state, "state_hash": C.digest(state)})

func _forged_creation_marker_cannot_reduce_floor() -> void:
	var blueprint := BP.create(_genome(), _policy())
	_check(not blueprint.is_empty(), "forge_blueprint_valid")
	if blueprint.is_empty(): return
	var entry := R.individual(blueprint, "rm34.forge", [500, 0, 500], B.stock(100000))
	_check(not entry.is_empty(), "forge_founder_valid")
	if entry.is_empty(): return
	var run := _run_ticks(entry, _field("rm34.forge.field"), 6)
	_check(run.success, "forge_runtime_witness_runs:" + String(run.get("error", "")))
	if not run.success: return
	var state: Dictionary = run.entry.state
	_check(state.development.modules.size() == 2 and state.development.grant_seq >= 3, "forge_persistent_support_present")
	_check(LS.validate(state, blueprint).is_empty(), "forge_untampered_state_valid")

	var marker_only: Dictionary = state.duplicate(true)
	marker_only.development.last_events = [{"tip": "p000000", "rule": "start", "outcome": "MODULE_CREATED"}]
	_check(LS.validate(marker_only, blueprint).is_empty(), "syntactic_creation_marker_does_not_change_valid_floor")

	var water_per_module: int = int(blueprint.life_history.metabolism.maintenance_water_per_module_mg)
	var energy_per_module: int = int(blueprint.life_history.metabolism.maintenance_energy_per_module_mj)
	var root_only_water: int = int(marker_only.development.grant_seq) * water_per_module
	var root_only_energy: int = int(marker_only.development.grant_seq) * energy_per_module
	var refund_water: int = int(marker_only.resource_ledger.maintenance.water_mg) - root_only_water
	var refund_energy: int = int(marker_only.resource_ledger.maintenance.energy_mj) - root_only_energy
	_check(refund_water > 0 and refund_energy > 0, "forged_marker_refund_is_nonzero")
	var forged: Dictionary = marker_only.duplicate(true)
	forged.resource_ledger.maintenance.water_mg = root_only_water
	forged.resource_ledger.maintenance.energy_mj = root_only_energy
	forged.metabolic_reserves.water_mg += refund_water
	forged.metabolic_reserves.energy_mj += refund_energy
	_check(LS.validate(forged, blueprint) == "LIFE_MAINTENANCE_HISTORY", "forged_marker_refund_rejected")
	_check(LS.serialize(forged, blueprint).is_empty(), "forged_marker_refund_not_serializable")
	_check(LS.deserialize(_encoded_state_file(blueprint, forged)).is_empty(), "forged_marker_refund_deserialize_rejected")

	var bounded: Dictionary = marker_only.duplicate(true)
	var minimum_water: int = root_only_water + water_per_module
	var minimum_energy: int = root_only_energy + energy_per_module
	bounded.metabolic_reserves.water_mg += int(bounded.resource_ledger.maintenance.water_mg) - minimum_water
	bounded.metabolic_reserves.energy_mj += int(bounded.resource_ledger.maintenance.energy_mj) - minimum_energy
	bounded.resource_ledger.maintenance.water_mg = minimum_water
	bounded.resource_ledger.maintenance.energy_mj = minimum_energy
	_check(LS.validate(bounded, blueprint).is_empty(), "one_birth_payment_boundary_valid_despite_forged_marker")
	_check(not LS.serialize(bounded, blueprint).is_empty(), "one_birth_payment_boundary_serializable")

func _unfunded_birth_maintenance_rolls_back_candidate_growth() -> void:
	var blueprint := BP.create(_genome(1), _policy(1000))
	_check(not blueprint.is_empty(), "rollback_blueprint_valid")
	if blueprint.is_empty(): return
	var entry := R.individual(blueprint, "rm34.rollback", [500, 0, 500], {"material_mg": 10, "water_mg": 5, "energy_mj": 5})
	_check(not entry.is_empty(), "rollback_founder_valid")
	if entry.is_empty(): return
	var field := _field("rm34.rollback.field")
	var result := R.step_population(field, [entry], field.owner_token, field.owner_epoch, field.revision)
	_check(result.success, "rollback_step_succeeds_without_partial_growth")
	if not result.success: return
	var state: Dictionary = result.population[0].state
	_check(state.development.modules.size() == 1 and state.development.received == B.stock(), "rollback_keeps_pre_growth_development")
	_check(state.resource_ledger.growth_transferred == B.stock(), "rollback_keeps_growth_ledger_zero")
	_check(state.resource_ledger.maintenance.water_mg == 2 and state.resource_ledger.maintenance.energy_mj == 3, "rollback_keeps_only_preexisting_root_maintenance")
	_check(LS.validate(state, blueprint).is_empty(), "rollback_state_valid")
