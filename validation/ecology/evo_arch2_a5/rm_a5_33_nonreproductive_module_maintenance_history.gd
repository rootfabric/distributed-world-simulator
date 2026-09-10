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
	_nonreproductive_support_module_strengthens_maintenance_floor()
	_latest_created_module_is_not_charged_retroactively()
	print("EVO_ARCH2_A5_RM33 assertions=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _check(value: bool, name: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		push_error("FAIL:" + name)

func _genome() -> Dictionary:
	var leaf := P.rule("leaf", [P.action("retire")])
	var start := P.rule("start", [
		P.action("extend", "support", [0, 10, 0], 1),
		P.action("branch", "support", [0, 0, 0], 0, 0, 0, "leaf"),
		P.action("retire"),
	])
	return G.create({"schema": P.SCHEMA, "entry": "start", "max_age": 32, "max_depth": 2, "rules": [start, leaf]}, "RM-A5-33 nonreproductive support maintenance witness")

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
	policy.survival.starvation_limit_ticks = 100
	policy.reproduction.maturity_ticks = 100
	policy.reproduction.interval_ticks = 100
	policy.reproduction.required_reproductive_modules = 0
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

func _nonreproductive_support_module_strengthens_maintenance_floor() -> void:
	var blueprint := BP.create(_genome(), _policy())
	_check(not blueprint.is_empty(), "blueprint_valid")
	if blueprint.is_empty(): return
	var entry := R.individual(blueprint, "rm33.organism", [500, 0, 500], B.stock(100000))
	_check(not entry.is_empty(), "founder_valid")
	if entry.is_empty(): return
	var run := _run_ticks(entry, _field("rm33.field"), 6)
	_check(run.success, "funded_runtime_witness_runs:" + String(run.get("error", "")))
	if not run.success: return
	var state: Dictionary = run.entry.state
	_check(state.reproduction_count == 0, "witness_has_no_reproduction")
	_check(state.development.modules.size() == 2 and state.development.grant_seq >= 3, "persistent_support_history_present")
	_check(LS.validate(state, blueprint).is_empty(), "untampered_runtime_state_valid")

	var root_only_water: int = int(state.development.grant_seq) * int(blueprint.life_history.metabolism.maintenance_water_per_module_mg)
	var root_only_energy: int = int(state.development.grant_seq) * int(blueprint.life_history.metabolism.maintenance_energy_per_module_mj)
	var refund_water: int = int(state.resource_ledger.maintenance.water_mg) - root_only_water
	var refund_energy: int = int(state.resource_ledger.maintenance.energy_mj) - root_only_energy
	_check(refund_water > 0 and refund_energy > 0, "reviewer_refund_is_nonzero")
	var tampered: Dictionary = state.duplicate(true)
	tampered.resource_ledger.maintenance.water_mg = root_only_water
	tampered.resource_ledger.maintenance.energy_mj = root_only_energy
	tampered.metabolic_reserves.water_mg += refund_water
	tampered.metabolic_reserves.energy_mj += refund_energy
	_check(LS.validate(tampered, blueprint) == "LIFE_MAINTENANCE_HISTORY", "root_only_refund_splice_rejected")
	_check(LS.serialize(tampered, blueprint).is_empty(), "root_only_refund_not_serializable")
	_check(LS.deserialize(_encoded_state_file(blueprint, tampered)).is_empty(), "root_only_refund_deserialize_rejected")

	var bounded: Dictionary = state.duplicate(true)
	var minimum_water: int = root_only_water + int(blueprint.life_history.metabolism.maintenance_water_per_module_mg)
	var minimum_energy: int = root_only_energy + int(blueprint.life_history.metabolism.maintenance_energy_per_module_mj)
	bounded.metabolic_reserves.water_mg += int(bounded.resource_ledger.maintenance.water_mg) - minimum_water
	bounded.metabolic_reserves.energy_mj += int(bounded.resource_ledger.maintenance.energy_mj) - minimum_energy
	bounded.resource_ledger.maintenance.water_mg = minimum_water
	bounded.resource_ledger.maintenance.energy_mj = minimum_energy
	_check(LS.validate(bounded, blueprint).is_empty(), "conservative_one_nonroot_tick_boundary_valid")
	_check(not LS.serialize(bounded, blueprint).is_empty(), "conservative_boundary_serializable")

func _latest_created_module_is_not_charged_retroactively() -> void:
	var blueprint := BP.create(_genome(), _policy())
	var entry := R.individual(blueprint, "rm33.latest", [500, 0, 500], B.stock(100000))
	var field := _field("rm33.latest.field")
	var result := R.step_population(field, [entry], field.owner_token, field.owner_epoch, field.revision)
	_check(result.success, "single_tick_runtime_runs")
	if not result.success: return
	var state: Dictionary = result.population[0].state
	_check(state.development.modules.size() == 2, "support_created_on_latest_tick")
	_check(state.resource_ledger.maintenance.water_mg == blueprint.life_history.metabolism.maintenance_water_per_module_mg, "latest_module_not_water_charged_before_creation")
	_check(state.resource_ledger.maintenance.energy_mj == blueprint.life_history.metabolism.maintenance_energy_per_module_mj, "latest_module_not_energy_charged_before_creation")
	_check(LS.validate(state, blueprint).is_empty(), "latest_created_module_state_remains_valid")
