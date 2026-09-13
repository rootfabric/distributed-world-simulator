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
	_exact_parent_preimage_is_required()
	print("EVO_ARCH2_A5_RM27 assertions=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _check(value: bool, name: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		push_error("FAIL:" + name)

func _genome() -> Dictionary:
	var start := P.rule("start", [P.action("differentiate", "reproductive", [0, 10, 0], 1), P.action("retire")], "start")
	return G.create({"schema": P.SCHEMA, "entry": "start", "max_age": 8, "max_depth": 1, "rules": [start]}, "RM-A5-27 exact parent preimage witness")

func _policy() -> Dictionary:
	var policy := LH.create_default()
	policy.uptake.basal_water_mg = 1000
	policy.uptake.basal_nutrient_mg = 1000
	policy.uptake.basal_organic_mg = 1000
	policy.uptake.water_per_absorber_unit_mg = 0
	policy.uptake.nutrient_per_absorber_unit_mg = 0
	policy.uptake.organic_per_absorber_unit_mg = 0
	policy.metabolism.maintenance_water_per_module_mg = 0
	policy.metabolism.maintenance_energy_per_module_mj = 0
	policy.growth.transfer_permille = 500
	policy.growth.max_transfer = B.stock(10000)
	policy.reproduction.maturity_ticks = 1
	policy.reproduction.interval_ticks = 10
	policy.reproduction.required_reproductive_modules = 1
	policy.reproduction.offspring_per_event = 1
	policy.reproduction.endowment = {"material_mg": 11, "water_mg": 7, "energy_mj": 5}
	policy.reproduction.fee_energy_mj = 0
	return policy

func _field(owner: String) -> Dictionary:
	return Field.create(owner, 1, [0, 0, 0], 1000, 1, 1, F.stock(900000), F.stock(1000000), F.signals(1000, 500, 0, 0))

func _encoded_state_file(blueprint: Dictionary, state: Dictionary) -> String:
	return C.encode({"schema": "dws.ecology.life-state-file.v1", "blueprint": blueprint, "state": state, "state_hash": C.digest(state)})

func _exact_parent_preimage_is_required() -> void:
	var blueprint := BP.create(_genome(), _policy())
	_check(not blueprint.is_empty(), "blueprint_valid")

	var fake_parent_id := "rm27.fake.parent"
	var sequence := 0
	var child_id := LS.propagule_id(fake_parent_id, sequence)
	var forged := LS.create(blueprint, child_id, [500, 0, 500], blueprint.life_history.reproduction.endowment, "FOUNDER_ENDOWMENT")
	_check(not forged.is_empty(), "seed_shaped_founder_control")
	forged.origin_kind = "PARENT_TRANSFER"
	forged.origin_receipt = {
		"schema": LS.PARENT_TRANSFER_RECEIPT_SCHEMA,
		"blueprint_hash": BP.biological_hash(blueprint),
		"parent_id": fake_parent_id,
		"sequence": sequence,
		"birth_tick": 1,
		"position_mm": [500, 0, 500],
		"endowment": blueprint.life_history.reproduction.endowment.duplicate(true),
		"parent_state_hash": "0".repeat(64),
		"parent_state": {},
	}
	_check(LS.validate(forged, blueprint) == "LIFE_PARENT_TRANSFER_PARENT_STATE", "arbitrary_hash_without_parent_preimage_rejected")
	_check(LS.serialize(forged, blueprint).is_empty(), "arbitrary_hash_receipt_not_serializable")
	_check(LS.deserialize(_encoded_state_file(blueprint, forged)).is_empty(), "arbitrary_hash_receipt_deserialize_rejected")

	var fake_parent := LS.create(blueprint, fake_parent_id, [500, 0, 500], B.stock(30000), "FOUNDER_ENDOWMENT")
	_check(not fake_parent.is_empty(), "valid_founder_parent_without_reproduction_exists")
	var coherent_fake: Dictionary = forged.duplicate(true)
	coherent_fake.origin_receipt.parent_state = fake_parent
	coherent_fake.origin_receipt.parent_state_hash = C.digest(fake_parent)
	_check(LS.validate(coherent_fake, blueprint) == "LIFE_PARENT_TRANSFER_PARENT_STATE", "valid_parent_without_paid_reproduction_rejected")

	var parent := R.individual(blueprint, "rm27.real.parent", [500, 0, 500], B.stock(30000))
	var field := _field("rm27.real.field")
	var reproduced := R.step_population(field, [parent], field.owner_token, field.owner_epoch, field.revision)
	_check(reproduced.success and reproduced.propagules.size() == 1, "real_paid_parent_reproduces")
	if not reproduced.success or reproduced.propagules.is_empty(): return
	var paid_parent_state: Dictionary = reproduced.population[0].state
	var child := R.materialize_propagule(reproduced.propagules[0], blueprint, paid_parent_state)
	_check(not child.is_empty() and child.state.origin_receipt.parent_state == paid_parent_state, "materialized_child_embeds_exact_paid_parent_state")
	_check(LS.validate(child.state, blueprint).is_empty(), "exact_parent_preimage_child_valid")
	var persisted := LS.serialize(child.state, blueprint)
	_check(not persisted.is_empty() and not LS.deserialize(persisted).is_empty(), "exact_parent_preimage_survives_restart")

	var wrong_hash: Dictionary = child.state.duplicate(true)
	wrong_hash.origin_receipt.parent_state_hash = "f".repeat(64)
	_check(LS.validate(wrong_hash, blueprint) == "LIFE_PARENT_TRANSFER_PARENT_STATE", "receipt_hash_must_match_exact_parent_preimage")

	var unpaid_parent: Dictionary = child.state.duplicate(true)
	var refund_material: int = int(blueprint.life_history.reproduction.endowment.material_mg)
	unpaid_parent.origin_receipt.parent_state.resource_ledger.reproduction_transferred.material_mg -= refund_material
	unpaid_parent.origin_receipt.parent_state.metabolic_reserves.material_mg += refund_material
	unpaid_parent.origin_receipt.parent_state_hash = C.digest(unpaid_parent.origin_receipt.parent_state)
	_check(LS.validate(unpaid_parent, blueprint) == "LIFE_PARENT_TRANSFER_PARENT_STATE", "coherent_unpaid_parent_preimage_rejected")