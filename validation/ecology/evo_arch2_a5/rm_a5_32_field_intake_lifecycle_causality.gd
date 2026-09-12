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
	_age_zero_parent_transfer_cannot_mint_field_intake()
	_per_resource_intake_is_bounded_by_lifecycle_age()
	print("EVO_ARCH2_A5_RM32 assertions=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _check(value: bool, name: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		push_error("FAIL:" + name)

func _genome() -> Dictionary:
	var start := P.rule("start", [P.action("differentiate", "reproductive", [0, 10, 0], 1), P.action("retire")], "start")
	return G.create({"schema": P.SCHEMA, "entry": "start", "max_age": 8, "max_depth": 1, "rules": [start]}, "RM-A5-32 field intake causality witness")

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

func _age_zero_parent_transfer_cannot_mint_field_intake() -> void:
	var blueprint := BP.create(_genome(), _policy())
	_check(not blueprint.is_empty(), "blueprint_valid")
	if blueprint.is_empty(): return
	var parent := R.individual(blueprint, "rm32.parent", [500, 0, 500], B.stock(30000))
	var field := _field("rm32.parent.field")
	var reproduced := R.step_population(field, [parent], field.owner_token, field.owner_epoch, field.revision)
	_check(reproduced.success and reproduced.propagules.size() == 1, "real_parent_reproduces")
	if not reproduced.success or reproduced.propagules.is_empty(): return
	var child := R.materialize_propagule(reproduced.propagules[0], blueprint, reproduced.population[0].state)
	_check(not child.is_empty() and child.state.age_ticks == 0, "age_zero_parent_transfer_child_created")
	if child.is_empty(): return
	_check(LS.validate(child.state, blueprint).is_empty(), "untampered_child_valid")

	var tampered: Dictionary = child.state.duplicate(true)
	tampered.resource_ledger.field_intake.nutrient_mg += 1
	tampered.resource_ledger.assimilated.material_mg += 1
	tampered.metabolic_reserves.material_mg += 1
	_check(LS.validate(tampered, blueprint) == "LIFE_FIELD_INTAKE_CAUSALITY", "age_zero_coherent_mass_mint_rejected")
	_check(LS.serialize(tampered, blueprint).is_empty(), "age_zero_mass_mint_not_serializable")
	_check(LS.deserialize(_encoded_state_file(blueprint, tampered)).is_empty(), "age_zero_mass_mint_deserialize_rejected")
	var step := R.step_population(reproduced.field, [{"blueprint": blueprint, "state": tampered}], reproduced.field.owner_token, reproduced.field.owner_epoch, reproduced.field.revision)
	_check(not step.success and step.error == "A5_ENTRY_INVALID", "age_zero_mass_mint_runtime_admission_rejected")

	var forged_source: Dictionary = child.state.duplicate(true)
	forged_source.last_environment_source = {
		"owner_token": reproduced.field.owner_token,
		"owner_epoch": reproduced.field.owner_epoch,
		"revision": reproduced.field.revision,
		"tick": reproduced.field.tick,
		"field_hash": Field.state_hash(reproduced.field),
	}
	_check(LS.validate(forged_source, blueprint) == "LIFE_FIELD_INTAKE_CAUSALITY", "age_zero_environment_source_claim_rejected")

func _per_resource_intake_is_bounded_by_lifecycle_age() -> void:
	var blueprint := BP.create(_genome(), _policy())
	var state := LS.create(blueprint, "rm32.age.bound", [500, 0, 500], B.stock())
	_check(not state.is_empty(), "age_bound_founder_valid")
	if state.is_empty(): return
	state.age_ticks = 1
	state.resource_ledger.field_intake.water_mg = F.MAX_REQUEST + 1
	state.resource_ledger.assimilated.water_mg = F.MAX_REQUEST + 1
	state.metabolic_reserves.water_mg = F.MAX_REQUEST + 1
	_check(LS.validate(state, blueprint) == "LIFE_FIELD_INTAKE_CAUSALITY", "single_tick_water_over_request_cap_rejected")

	var nutrient: Dictionary = state.duplicate(true)
	nutrient.resource_ledger.field_intake.water_mg = 0
	nutrient.resource_ledger.assimilated.water_mg = 0
	nutrient.metabolic_reserves.water_mg = 0
	nutrient.resource_ledger.field_intake.nutrient_mg = F.MAX_REQUEST + 1
	nutrient.resource_ledger.assimilated.material_mg = F.MAX_REQUEST + 1
	nutrient.metabolic_reserves.material_mg = F.MAX_REQUEST + 1
	_check(LS.validate(nutrient, blueprint) == "LIFE_FIELD_INTAKE_CAUSALITY", "single_tick_nutrient_over_request_cap_rejected")
