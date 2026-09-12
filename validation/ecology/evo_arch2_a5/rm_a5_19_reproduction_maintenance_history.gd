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
	_reproduction_requires_paid_maintenance_history()
	print("EVO_ARCH2_A5_RM19 assertions=%d failed=%d" % [passed, failed])
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
	return G.create({"schema": P.SCHEMA, "entry": "start", "max_age": 12, "max_depth": 2, "rules": [start, leaf]}, "RM-A5-19 maintenance-paid reproduction witness")

func _policy() -> Dictionary:
	var policy := LH.create_default()
	policy.uptake.basal_water_mg = 5000
	policy.uptake.basal_nutrient_mg = 5000
	policy.uptake.basal_organic_mg = 5000
	policy.uptake.water_per_absorber_unit_mg = 0
	policy.uptake.nutrient_per_absorber_unit_mg = 0
	policy.uptake.organic_per_absorber_unit_mg = 0
	policy.metabolism.maintenance_energy_per_module_mj = 7
	policy.metabolism.maintenance_water_per_module_mg = 5
	policy.growth.transfer_permille = 500
	policy.growth.max_transfer = B.stock(20000)
	policy.reproduction.maturity_ticks = 1
	policy.reproduction.interval_ticks = 2
	policy.reproduction.offspring_per_event = 1
	policy.reproduction.endowment = B.stock()
	policy.reproduction.fee_energy_mj = 0
	return policy

func _field() -> Dictionary:
	return Field.create("rm19.rich.field", 1, [0, 0, 0], 1000, 1, 1, F.stock(900000), F.stock(1000000), F.signals(900, 500, 0, 0))

func _encoded_state_file(blueprint: Dictionary, state: Dictionary) -> String:
	return C.encode({
		"schema": "dws.ecology.life-state-file.v1",
		"blueprint": blueprint,
		"state": state,
		"state_hash": C.digest(state),
	})

func _reproduction_requires_paid_maintenance_history() -> void:
	var policy := _policy()
	var blueprint := BP.create(_genome(), policy)
	var entry := R.individual(blueprint, "rm19.parent", [500, 0, 500], B.stock(30000))
	_check(not blueprint.is_empty() and not entry.is_empty(), "maintenance_history_entry_valid")
	if entry.is_empty(): return
	var field := _field()
	var result := R.step_population(field, [entry], field.owner_token, field.owner_epoch, field.revision)
	_check(result.success and result.propagules.size() == 1, "maintenance_paid_reproduction_occurs")
	if not result.success: return
	var state: Dictionary = result.population[0].state
	_check(LS.validate(state, blueprint).is_empty(), "maintenance_paid_reproduction_state_valid")
	_check(state.reproduction_count == 1, "maintenance_paid_reproduction_count_one")
	# RM34 atomically charges birth maintenance for the newly committed reproductive
	# module. The first reproduction tick therefore contains one root payment plus
	# one birth payment for that module.
	_check(state.resource_ledger.maintenance.water_mg == 2 * policy.metabolism.maintenance_water_per_module_mg and state.resource_ledger.maintenance.energy_mj == 2 * policy.metabolism.maintenance_energy_per_module_mj, "first_event_root_plus_birth_maintenance_exact")

	var energy_tamper: Dictionary = state.duplicate(true)
	energy_tamper.resource_ledger.maintenance.energy_mj -= 1
	energy_tamper.metabolic_reserves.energy_mj += 1
	_check(LS.validate(energy_tamper, blueprint) == "LIFE_REPRODUCTION_MAINTENANCE", "compensated_unpaid_energy_maintenance_rejected")
	_check(LS.serialize(energy_tamper, blueprint).is_empty(), "unpaid_energy_maintenance_not_serializable")

	var water_tamper: Dictionary = state.duplicate(true)
	water_tamper.resource_ledger.maintenance.water_mg -= 1
	water_tamper.metabolic_reserves.water_mg += 1
	_check(LS.validate(water_tamper, blueprint) == "LIFE_REPRODUCTION_MAINTENANCE", "compensated_unpaid_water_maintenance_rejected")
	_check(LS.deserialize(_encoded_state_file(blueprint, water_tamper)).is_empty(), "unpaid_water_maintenance_deserialize_rejected")

	var text := LS.serialize(state, blueprint)
	var restored := LS.deserialize(text)
	_check(not text.is_empty() and not restored.is_empty(), "paid_maintenance_history_roundtrip_valid")
