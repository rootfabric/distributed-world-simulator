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
	_parent_transfer_state_requires_receipt()
	print("EVO_ARCH2_A5_RM23 assertions=%d failed=%d" % [passed, failed])
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
	return G.create({"schema": P.SCHEMA, "entry": "start", "max_age": 12, "max_depth": 2, "rules": [start, leaf]}, "RM-A5-23 state provenance witness")

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
	policy.reproduction.interval_ticks = 10
	policy.reproduction.offspring_per_event = 1
	policy.reproduction.endowment = {"material_mg": 7, "water_mg": 5, "energy_mj": 3}
	policy.reproduction.fee_energy_mj = 0
	return policy

func _field(owner: String) -> Dictionary:
	return Field.create(owner, 1, [0, 0, 0], 1000, 1, 1, F.stock(900000), F.stock(1000000), F.signals(1000, 500, 0, 0))

func _encoded_state_file(blueprint: Dictionary, state: Dictionary) -> String:
	return C.encode({"schema": "dws.ecology.life-state-file.v1", "blueprint": blueprint, "state": state, "state_hash": C.digest(state)})

func _parent_transfer_state_requires_receipt() -> void:
	var blueprint := BP.create(_genome(), _policy())
	_check(not blueprint.is_empty(), "blueprint_valid")
	var direct := LS.create(blueprint, "rm23.direct", [500, 0, 500], B.stock(B.MAX_STOCK), "PARENT_TRANSFER")
	_check(direct.is_empty(), "ls_create_rejects_parent_transfer")

	var seed_id := LS.propagule_id("rm23.fake.parent", 3)
	var seed_founder := LS.create(blueprint, seed_id, [500, 0, 500], blueprint.life_history.reproduction.endowment, "FOUNDER_ENDOWMENT")
	_check(not seed_founder.is_empty(), "seed_shaped_founder_control_valid")
	var forged: Dictionary = seed_founder.duplicate(true)
	forged.origin_kind = "PARENT_TRANSFER"
	_check(LS.validate(forged, blueprint) == "LIFE_PARENT_TRANSFER_RECEIPT", "manual_origin_flip_without_receipt_rejected")
	_check(LS.serialize(forged, blueprint).is_empty(), "manual_forge_not_serializable")
	_check(LS.deserialize(_encoded_state_file(blueprint, forged)).is_empty(), "manual_forge_deserialize_rejected")
	var forged_step := R.step_population(_field("rm23.forged.field"), [{"blueprint": blueprint, "state": forged}], "rm23.forged.field", 1, 0)
	_check(not forged_step.success and forged_step.error == "A5_ENTRY_INVALID", "manual_forge_population_rejected")

	var parent := R.individual(blueprint, "rm23.parent", [500, 0, 500], B.stock(30000))
	_check(not parent.is_empty(), "real_parent_created")
	var field := _field("rm23.parent.field")
	var reproduced := R.step_population(field, [parent], field.owner_token, field.owner_epoch, field.revision)
	_check(reproduced.success and reproduced.propagules.size() == 1, "real_parent_reproduces")
	if not reproduced.success or reproduced.propagules.is_empty(): return
	var parent_state: Dictionary = reproduced.population[0].state
	var propagule: Dictionary = reproduced.propagules[0]
	var child := R.materialize_propagule(propagule, blueprint, parent_state)
	_check(not child.is_empty(), "witnessed_materialization_succeeds")
	if child.is_empty(): return
	_check(child.state.origin_kind == "PARENT_TRANSFER" and not child.state.origin_receipt.is_empty(), "child_carries_parent_receipt")
	_check(LS.validate(child.state, blueprint).is_empty(), "receipt_bound_child_valid")
	var persisted := LS.serialize(child.state, blueprint)
	_check(not persisted.is_empty() and not LS.deserialize(persisted).is_empty(), "receipt_survives_persistence")

	var no_receipt: Dictionary = child.state.duplicate(true)
	no_receipt.origin_receipt = {}
	_check(LS.validate(no_receipt, blueprint) == "LIFE_PARENT_TRANSFER_RECEIPT", "receipt_removal_rejected")

	var inflated: Dictionary = child.state.duplicate(true)
	inflated.origin_receipt.endowment = B.stock(B.MAX_STOCK)
	inflated.resource_ledger.initial = B.stock(B.MAX_STOCK)
	inflated.metabolic_reserves = B.stock(B.MAX_STOCK)
	_check(LS.validate(inflated, blueprint) == "LIFE_PARENT_TRANSFER_ENDOWMENT", "arbitrary_endowment_receipt_forge_rejected")

	var unpaid_receipt: Dictionary = child.state.duplicate(true)
	unpaid_receipt.origin_receipt.parent_reproduction_transferred.material_mg -= blueprint.life_history.reproduction.endowment.material_mg
	_check(LS.validate(unpaid_receipt, blueprint) == "LIFE_PARENT_TRANSFER_PAYMENT", "unpaid_parent_receipt_rejected")