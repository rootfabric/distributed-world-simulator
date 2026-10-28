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
	_paid_reproduction_ledger_binding()
	print("EVO_ARCH2_A5_RM15 assertions=%d failed=%d" % [passed, failed])
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
	return G.create({"schema": P.SCHEMA, "entry": "start", "max_age": 12, "max_depth": 2, "rules": [start, leaf]}, "RM-A5-15 paid reproduction ledger witness")

func _policy() -> Dictionary:
	var policy := LH.create_default()
	policy.uptake.basal_water_mg = 5000
	policy.uptake.basal_nutrient_mg = 5000
	policy.uptake.basal_organic_mg = 5000
	policy.uptake.water_per_absorber_unit_mg = 0
	policy.uptake.nutrient_per_absorber_unit_mg = 0
	policy.uptake.organic_per_absorber_unit_mg = 0
	policy.metabolism.maintenance_energy_per_module_mj = 0
	policy.metabolism.maintenance_water_per_module_mg = 0
	policy.growth.transfer_permille = 500
	policy.growth.max_transfer = B.stock(20000)
	policy.reproduction.maturity_ticks = 1
	policy.reproduction.interval_ticks = 2
	policy.reproduction.offspring_per_event = 2
	policy.reproduction.endowment = {"material_mg": 3, "water_mg": 2, "energy_mj": 1}
	policy.reproduction.fee_energy_mj = 4
	return policy

func _field() -> Dictionary:
	return Field.create("rm15.rich.field", 1, [0, 0, 0], 1000, 1, 1, F.stock(900000), F.stock(1000000), F.signals(900, 500, 0, 0))

func _encoded_state_file(blueprint: Dictionary, state: Dictionary) -> String:
	return C.encode({
		"schema": "dws.ecology.life-state-file.v1",
		"blueprint": blueprint,
		"state": state,
		"state_hash": C.digest(state),
	})

func _paid_reproduction_ledger_binding() -> void:
	var blueprint := BP.create(_genome(), _policy())
	var entry := R.individual(blueprint, "rm15.parent", [500, 0, 500], B.stock(30000))
	_check(not blueprint.is_empty() and not entry.is_empty(), "paid_reproduction_entry_valid")
	if entry.is_empty(): return
	var field := _field()
	var result := R.step_population(field, [entry], field.owner_token, field.owner_epoch, field.revision)
	_check(result.success and result.propagules.size() == 2, "paid_reproduction_event_emits_two")
	if not result.success: return
	var state: Dictionary = result.population[0].state
	_check(LS.validate(state, blueprint).is_empty(), "paid_reproduction_state_valid")
	_check(state.reproduction_count == 2 and state.propagule_seq == 2, "paid_reproduction_counters_match_offspring")
	var endowment: Dictionary = blueprint.life_history.reproduction.endowment
	var transfer_exact := true
	for name in B.RESOURCES:
		transfer_exact = transfer_exact and state.resource_ledger.reproduction_transferred[name] == state.reproduction_count * endowment[name]
	_check(transfer_exact, "paid_reproduction_transfer_exact_per_child")
	_check(state.resource_ledger.reproduction_cost.material_mg == 0 and state.resource_ledger.reproduction_cost.water_mg == 0 and state.resource_ledger.reproduction_cost.energy_mj == state.reproduction_count * blueprint.life_history.reproduction.fee_energy_mj, "paid_reproduction_fee_exact_per_child")

	var transfer_tamper: Dictionary = state.duplicate(true)
	transfer_tamper.resource_ledger.reproduction_transferred.material_mg -= 1
	transfer_tamper.metabolic_reserves.material_mg += 1
	_check(LS.validate(transfer_tamper, blueprint) == "LIFE_REPRODUCTION_TRANSFER_material_mg", "unpaid_transfer_history_rejected_before_conservation_escape")
	_check(LS.serialize(transfer_tamper, blueprint).is_empty(), "unpaid_transfer_history_not_serializable")

	var cost_tamper: Dictionary = state.duplicate(true)
	cost_tamper.resource_ledger.reproduction_cost.energy_mj -= 1
	cost_tamper.metabolic_reserves.energy_mj += 1
	_check(LS.validate(cost_tamper, blueprint) == "LIFE_REPRODUCTION_COST_energy_mj", "unpaid_fee_history_rejected_before_conservation_escape")
	_check(LS.deserialize(_encoded_state_file(blueprint, cost_tamper)).is_empty(), "unpaid_fee_history_deserialize_rejected")

	var text := LS.serialize(state, blueprint)
	_check(not text.is_empty(), "paid_reproduction_state_serializes")
	var restored := LS.deserialize(text)
	_check(not restored.is_empty() and LS.state_hash(restored.state, restored.blueprint) == LS.state_hash(state, blueprint), "paid_reproduction_roundtrip_exact")
