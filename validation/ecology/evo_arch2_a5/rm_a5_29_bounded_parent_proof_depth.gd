extends SceneTree

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
	_lineage_proof_depth_is_explicitly_bounded()
	print("EVO_ARCH2_A5_RM29 assertions=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _check(value: bool, name: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		push_error("FAIL:" + name)

func _genome() -> Dictionary:
	var start := P.rule("start", [P.action("differentiate", "reproductive", [0, 10, 0], 1), P.action("retire")], "start")
	return G.create({"schema": P.SCHEMA, "entry": "start", "max_age": 8, "max_depth": 1, "rules": [start]}, "RM-A5-29 bounded lineage proof witness")

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

func _proof_depth(state: Dictionary) -> int:
	var depth := 0
	var current := state
	while current.origin_kind == "PARENT_TRANSFER":
		depth += 1
		if depth > LS.MAX_PARENT_PROOF_DEPTH + 1: return depth
		if not current.origin_receipt is Dictionary or not current.origin_receipt.has("parent_state") or not current.origin_receipt.parent_state is Dictionary:
			return -1
		current = current.origin_receipt.parent_state
	return depth

func _next_generation(entry: Dictionary, blueprint: Dictionary, generation: int) -> Dictionary:
	var field := _field("rm29.field.%02d" % generation)
	var reproduced := R.step_population(field, [entry], field.owner_token, field.owner_epoch, field.revision)
	if not reproduced.success:
		return {"success": false, "error": "step:%s" % String(reproduced.get("error", "unknown"))}
	if reproduced.propagules.size() != 1:
		return {"success": false, "error": "propagules:%d" % reproduced.propagules.size()}
	var parent_state: Dictionary = reproduced.population[0].state
	var witness_error := LS.validate_parent_transfer_witness(reproduced.propagules[0], blueprint, parent_state)
	if not witness_error.is_empty():
		return {"success": false, "error": "witness:%s" % witness_error}
	var child := R.materialize_propagule(reproduced.propagules[0], blueprint, parent_state)
	if child.is_empty():
		return {"success": false, "error": "materialize:empty"}
	return {"success": true, "child": child, "parent": reproduced.population[0], "propagule": reproduced.propagules[0]}

func _lineage_proof_depth_is_explicitly_bounded() -> void:
	var blueprint := BP.create(_genome(), _policy())
	_check(not blueprint.is_empty(), "blueprint_valid")
	_check(LS.MAX_PARENT_PROOF_DEPTH == 8, "research_depth_cap_matches_canonical_budget")
	var current := R.individual(blueprint, "rm29.founder", [500, 0, 500], B.stock(10000))
	_check(not current.is_empty(), "founder_valid")
	var all_bounded_generations_valid := true
	var failure_detail := ""
	for generation in range(1, LS.MAX_PARENT_PROOF_DEPTH + 1):
		var next := _next_generation(current, blueprint, generation)
		if not next.success:
			all_bounded_generations_valid = false
			failure_detail = "generation=%d %s" % [generation, String(next.get("error", "unknown"))]
			break
		current = next.child
		var proof_depth := _proof_depth(current.state)
		var validation_error := LS.validate(current.state, blueprint)
		if proof_depth != generation or not validation_error.is_empty():
			all_bounded_generations_valid = false
			failure_detail = "generation=%d proof_depth=%d validate=%s" % [generation, proof_depth, validation_error]
			break
	_check(all_bounded_generations_valid, "all_generations_through_cap_materialize_and_validate:" + failure_detail)
	if not all_bounded_generations_valid: return
	_check(_proof_depth(current.state) == LS.MAX_PARENT_PROOF_DEPTH, "lineage_reaches_exact_cap")
	var persisted := LS.serialize(current.state, blueprint)
	_check(not persisted.is_empty() and not LS.deserialize(persisted).is_empty(), "cap_depth_state_roundtrips_canonically")

	var overflow_field := _field("rm29.overflow")
	var overflow_parent := R.step_population(overflow_field, [current], overflow_field.owner_token, overflow_field.owner_epoch, overflow_field.revision)
	_check(overflow_parent.success and overflow_parent.propagules.size() == 1, "cap_depth_parent_can_still_emit_paid_propagule")
	if not overflow_parent.success or overflow_parent.propagules.is_empty(): return
	var overflow_child := R.materialize_propagule(overflow_parent.propagules[0], blueprint, overflow_parent.population[0].state)
	_check(overflow_child.is_empty(), "generation_nine_fails_before_noncanonical_state")
	_check(LS.validate_parent_transfer_witness(overflow_parent.propagules[0], blueprint, overflow_parent.population[0].state) == "PROPAGULE_PARENT_STATE", "overflow_parent_witness_reports_bounded_failure")
