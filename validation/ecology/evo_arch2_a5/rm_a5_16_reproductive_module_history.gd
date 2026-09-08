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
const Fixtures = preload("res://scripts/research/ecology/v2/body_program_fixtures_v1.gd")
const H = preload("res://scripts/research/ecology/v2/phenotype_snapshot_v1.gd")

var passed := 0
var failed := 0

func _init() -> void:
	_missing_module_history_rejected()
	_reachable_module_history_accepted()
	print("EVO_ARCH2_A5_RM16 assertions=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _check(value: bool, name: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		push_error("FAIL:" + name)

func _zero_policy(maturity: int) -> Dictionary:
	var policy := LH.create_default()
	policy.uptake.basal_water_mg = 0
	policy.uptake.basal_nutrient_mg = 0
	policy.uptake.basal_organic_mg = 0
	policy.uptake.water_per_absorber_unit_mg = 0
	policy.uptake.nutrient_per_absorber_unit_mg = 0
	policy.uptake.organic_per_absorber_unit_mg = 0
	policy.metabolism.maintenance_energy_per_module_mj = 0
	policy.metabolism.maintenance_water_per_module_mg = 0
	policy.reproduction.maturity_ticks = maturity
	policy.reproduction.interval_ticks = 1
	policy.reproduction.required_reproductive_modules = 1
	policy.reproduction.offspring_per_event = 1
	policy.reproduction.endowment = B.stock()
	policy.reproduction.fee_energy_mj = 0
	return policy

func _reproductive_genome() -> Dictionary:
	var leaf := P.rule("leaf", [P.action("differentiate", "collector", [0, 20, 0], 1, 6000), P.action("retire")])
	var start := P.rule("start", [P.action("differentiate", "reproductive", [0, 10, 0], 1), P.action("branch", "support", [0, 0, 0], 0, 0, 0, "leaf")], "start")
	return G.create({"schema": P.SCHEMA, "entry": "start", "max_age": 12, "max_depth": 2, "rules": [start, leaf]}, "RM-A5-16 reproductive module history witness")

func _encoded_state_file(blueprint: Dictionary, state: Dictionary) -> String:
	return C.encode({
		"schema": "dws.ecology.life-state-file.v1",
		"blueprint": blueprint,
		"state": state,
		"state_hash": C.digest(state),
	})

func _missing_module_history_rejected() -> void:
	var policy := _zero_policy(1)
	policy.growth.transfer_permille = 0
	var blueprint := BP.create(Fixtures.make(0), policy)
	var entry := R.individual(blueprint, "rm16.root.only", [500, 0, 500], B.stock())
	_check(not blueprint.is_empty() and not entry.is_empty(), "root_only_entry_valid")
	if entry.is_empty(): return
	var impossible: Dictionary = entry.state.duplicate(true)
	impossible.age_ticks = 1
	impossible.reproduction_count = 1
	impossible.propagule_seq = 1
	impossible.next_reproduction_tick = 2
	_check(LS.validate(impossible, blueprint) == "LIFE_REPRODUCTION_MODULE_HISTORY", "root_only_positive_reproduction_history_rejected")
	_check(LS.serialize(impossible, blueprint).is_empty(), "root_only_history_not_serializable")
	_check(LS.deserialize(_encoded_state_file(blueprint, impossible)).is_empty(), "root_only_history_deserialize_rejected")

func _reachable_module_history_accepted() -> void:
	var policy := _zero_policy(2)
	policy.growth.transfer_permille = 500
	policy.growth.max_transfer = B.stock(20000)
	var blueprint := BP.create(_reproductive_genome(), policy)
	var entry := R.individual(blueprint, "rm16.reachable", [500, 0, 500], B.stock(30000))
	_check(not blueprint.is_empty() and not entry.is_empty(), "reachable_entry_valid")
	if entry.is_empty(): return
	var field := Field.create("rm16.rich.field", 1, [0, 0, 0], 1000, 1, 1, F.stock(900000), F.stock(1000000), F.signals(900, 500, 0, 0))
	var prepared := R.step_population(field, [entry], field.owner_token, field.owner_epoch, field.revision)
	var prepared_has_module := false
	if prepared.success:
		var phenotype := H.compile(prepared.population[0].state.development, blueprint.genome)
		prepared_has_module = int(phenotype.module_roles.get("reproductive", 0)) >= 1
	_check(prepared.success and prepared_has_module and prepared.population[0].state.reproduction_count == 0, "reproductive_module_exists_before_maturity")
	if not prepared.success: return
	var reproduced := R.step_population(prepared.field, prepared.population, prepared.field.owner_token, prepared.field.owner_epoch, prepared.field.revision)
	_check(reproduced.success and reproduced.propagules.size() == 1 and reproduced.population[0].state.reproduction_count == 1, "runtime_reproduction_with_required_module_success")
	if not reproduced.success: return
	var state: Dictionary = reproduced.population[0].state
	_check(LS.validate(state, blueprint).is_empty(), "reachable_reproduction_history_valid")
	var text := LS.serialize(state, blueprint)
	_check(not text.is_empty(), "reachable_reproduction_history_serializes")
	var restored := LS.deserialize(text)
	_check(not restored.is_empty() and LS.state_hash(restored.state, restored.blueprint) == LS.state_hash(state, blueprint), "reachable_module_history_roundtrip_exact")
