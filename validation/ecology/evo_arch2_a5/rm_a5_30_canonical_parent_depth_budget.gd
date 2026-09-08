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
	_canonical_depth_budget_matches_lineage_cap()
	print("EVO_ARCH2_A5_RM30 assertions=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _check(value: bool, name: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		push_error("FAIL:" + name)

func _nested(depth: int) -> Variant:
	var value: Variant = 0
	for _i in depth:
		value = {"v": value}
	return value

func _genome() -> Dictionary:
	var start := P.rule("start", [P.action("differentiate", "reproductive", [0, 10, 0], 1), P.action("retire")], "start")
	return G.create({"schema": P.SCHEMA, "entry": "start", "max_age": 8, "max_depth": 1, "rules": [start]}, "RM-A5-30 canonical lineage depth witness")

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
	policy.reproduction.endowment = B.stock()
	policy.reproduction.fee_energy_mj = 0
	return policy

func _field(owner: String) -> Dictionary:
	return Field.create(owner, 1, [0, 0, 0], 1000, 1, 1, F.stock(900000), F.stock(1000000), F.signals(1000, 500, 0, 0))

func _next_generation(entry: Dictionary, blueprint: Dictionary, generation: int) -> Dictionary:
	var field := _field("rm30.field.%02d" % generation)
	var reproduced := R.step_population(field, [entry], field.owner_token, field.owner_epoch, field.revision)
	if not reproduced.success or reproduced.propagules.size() != 1:
		return {"success": false}
	var parent_state: Dictionary = reproduced.population[0].state
	var child := R.materialize_propagule(reproduced.propagules[0], blueprint, parent_state)
	return {"success": not child.is_empty(), "child": child, "parent": reproduced.population[0], "propagule": reproduced.propagules[0]}

func _canonical_depth_budget_matches_lineage_cap() -> void:
	_check(not C.encode(_nested(24)).is_empty(), "canonical_depth_24_is_encodable")
	_check(C.encode(_nested(25)).is_empty(), "canonical_depth_25_is_rejected")
	_check(LS.MAX_PARENT_PROOF_DEPTH == 8, "a5_lineage_cap_is_eight")

	var blueprint := BP.create(_genome(), _policy())
	var current := R.individual(blueprint, "rm30.founder", [500, 0, 500], B.stock(10000))
	var through_cap := not current.is_empty()
	for generation in range(1, LS.MAX_PARENT_PROOF_DEPTH + 1):
		var next := _next_generation(current, blueprint, generation)
		if not next.success:
			through_cap = false
			break
		current = next.child
	_check(through_cap, "real_lineage_materializes_through_generation_eight")
	if not through_cap: return
	_check(not LS.serialize(current.state, blueprint).is_empty(), "generation_eight_state_is_canonical_and_serializable")

	var overflow_field := _field("rm30.overflow")
	var overflow_parent := R.step_population(overflow_field, [current], overflow_field.owner_token, overflow_field.owner_epoch, overflow_field.revision)
	_check(overflow_parent.success and overflow_parent.propagules.size() == 1, "generation_eight_parent_emits_paid_propagule")
	if not overflow_parent.success or overflow_parent.propagules.is_empty(): return
	var generation_nine := R.materialize_propagule(overflow_parent.propagules[0], blueprint, overflow_parent.population[0].state)
	_check(generation_nine.is_empty(), "generation_nine_materialization_fails_before_canonical_overflow")