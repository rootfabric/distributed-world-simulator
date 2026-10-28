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
	_paid_parent_binding()
	print("EVO_ARCH2_A5_RM18 assertions=%d failed=%d" % [passed, failed])
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
	return G.create({"schema": P.SCHEMA, "entry": "start", "max_age": 12, "max_depth": 2, "rules": [start, leaf]}, "RM-A5-18 exact paid parent propagule witness")

func _policy() -> Dictionary:
	var policy := LH.create_default()
	policy.uptake.basal_water_mg = 5000
	policy.uptake.basal_nutrient_mg = 5000
	policy.uptake.basal_organic_mg = 5000
	policy.uptake.water_per_absorber_unit_mg = 0
	policy.uptake.nutrient_per_absorber_unit_mg = 0
	policy.uptake.organic_per_absorber_unit_mg = 0
	policy.metabolism.maintenance_energy_per_module_mj = 2
	policy.metabolism.maintenance_water_per_module_mg = 1
	policy.growth.transfer_permille = 500
	policy.growth.max_transfer = B.stock(20000)
	policy.reproduction.maturity_ticks = 1
	policy.reproduction.interval_ticks = 2
	policy.reproduction.offspring_per_event = 1
	policy.reproduction.endowment = {"material_mg": 3, "water_mg": 2, "energy_mj": 1}
	policy.reproduction.fee_energy_mj = 4
	return policy

func _field() -> Dictionary:
	return Field.create("rm18.rich.field", 1, [0, 0, 0], 1000, 1, 1, F.stock(900000), F.stock(1000000), F.signals(900, 500, 0, 0))

func _paid_parent_binding() -> void:
	var blueprint := BP.create(_genome(), _policy())
	var parent := R.individual(blueprint, "rm18.parent", [500, 0, 500], B.stock(30000))
	_check(not blueprint.is_empty() and not parent.is_empty(), "paid_parent_entry_valid")
	if parent.is_empty(): return
	var field := _field()
	var result := R.step_population(field, [parent], field.owner_token, field.owner_epoch, field.revision)
	_check(result.success and result.propagules.size() == 1, "paid_parent_emits_one_propagule")
	if not result.success or result.propagules.is_empty(): return
	var paid_parent_state: Dictionary = result.population[0].state
	var propagule: Dictionary = result.propagules[0]
	_check(LS.validate(paid_parent_state, blueprint).is_empty(), "paid_parent_state_valid")
	_check(propagule.parent_state_hash == LS.state_hash(paid_parent_state, blueprint), "propagule_hash_matches_returned_paid_parent_state")
	_check(R.validate_propagule(propagule, blueprint, paid_parent_state).is_empty(), "propagule_valid_with_exact_paid_parent")
	_check(R.validate_propagule(propagule, blueprint) == "PROPAGULE_PARENT_STATE_REQUIRED", "propagule_without_paid_parent_fails_closed")
	_check(R.materialize_propagule(propagule, blueprint).is_empty(), "materialization_without_paid_parent_rejected")
	var child := R.materialize_propagule(propagule, blueprint, paid_parent_state)
	_check(not child.is_empty() and child.state.origin_kind == "PARENT_TRANSFER", "materialization_with_paid_parent_succeeds")

	var coherent_sequence: Dictionary = propagule.duplicate(true)
	coherent_sequence.sequence += 1
	coherent_sequence.id = R._propagule_id(coherent_sequence.parent_id, coherent_sequence.sequence)
	_check(R.validate_propagule(coherent_sequence, blueprint, paid_parent_state) == "PROPAGULE_PARENT_SEQUENCE", "coherent_sequence_and_id_forgery_rejected")

	var wrong_birth: Dictionary = propagule.duplicate(true)
	wrong_birth.birth_tick += 1
	_check(R.validate_propagule(wrong_birth, blueprint, paid_parent_state) == "PROPAGULE_PARENT_BIRTH", "birth_tick_not_in_paid_parent_event_rejected")

	var wrong_position: Dictionary = propagule.duplicate(true)
	wrong_position.position_mm[0] += 1
	_check(R.validate_propagule(wrong_position, blueprint, paid_parent_state) == "PROPAGULE_PARENT_POSITION", "propagule_position_not_in_paid_parent_event_rejected")

	var stale_parent_state: Dictionary = parent.state
	_check(R.validate_propagule(propagule, blueprint, stale_parent_state) == "PROPAGULE_PARENT_HASH", "stale_parent_state_cannot_authorize_materialization")
