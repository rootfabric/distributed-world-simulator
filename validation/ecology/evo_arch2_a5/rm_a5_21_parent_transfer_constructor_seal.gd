extends SceneTree

const B = preload("res://scripts/research/ecology/v2/body_graph_v1.gd")
const P = preload("res://scripts/research/ecology/v2/development_program_v1.gd")
const G = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
const LH = preload("res://scripts/research/ecology/v2/life_history_program_v1.gd")
const BP = preload("res://scripts/research/ecology/v2/organism_blueprint_v1.gd")
const R = preload("res://scripts/research/ecology/v2/resource_lifecycle_runtime_v1.gd")
const F = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const Field = preload("res://scripts/research/ecology/v2/local_environment_field_v1.gd")

var passed := 0
var failed := 0

func _init() -> void:
	_parent_transfer_constructor_is_sealed()
	print("EVO_ARCH2_A5_RM21 assertions=%d failed=%d" % [passed, failed])
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
	return G.create({"schema": P.SCHEMA, "entry": "start", "max_age": 12, "max_depth": 2, "rules": [start, leaf]}, "RM-A5-21 parent-transfer seal witness")

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

func _parent_transfer_constructor_is_sealed() -> void:
	var blueprint := BP.create(_genome(), _policy())
	_check(not blueprint.is_empty(), "blueprint_valid")
	var forged := R.individual(blueprint, "forged.child", [500, 0, 500], B.stock(B.MAX_STOCK), "PARENT_TRANSFER")
	_check(forged.is_empty(), "public_individual_rejects_parent_transfer")
	var founder := R.individual(blueprint, "rm21.parent", [500, 0, 500], B.stock(30000))
	_check(not founder.is_empty() and founder.state.origin_kind == "FOUNDER_ENDOWMENT", "founder_constructor_preserved")
	if founder.is_empty(): return
	var field := Field.create("rm21.rich.field", 1, [0, 0, 0], 1000, 1, 1, F.stock(900000), F.stock(1000000), F.signals(1000, 500, 0, 0))
	var reproduced := R.step_population(field, [founder], field.owner_token, field.owner_epoch, field.revision)
	_check(reproduced.success and reproduced.propagules.size() == 1, "real_paid_reproduction_emits_one")
	if not reproduced.success or reproduced.propagules.is_empty(): return
	var parent_state: Dictionary = reproduced.population[0].state
	var propagule: Dictionary = reproduced.propagules[0]
	_check(R.validate_propagule(propagule, blueprint, parent_state).is_empty(), "paid_propagule_valid")
	var child := R.materialize_propagule(propagule, blueprint, parent_state)
	_check(not child.is_empty() and child.state.origin_kind == "PARENT_TRANSFER", "verified_materialization_creates_parent_transfer")
	_check(child.state.metabolic_reserves == blueprint.life_history.reproduction.endowment, "verified_child_endowment_exact")
	_check(R.materialize_propagule(propagule, blueprint).is_empty(), "materialization_without_parent_witness_rejected")