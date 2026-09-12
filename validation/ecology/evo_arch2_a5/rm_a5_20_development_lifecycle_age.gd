extends SceneTree

const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const B = preload("res://scripts/research/ecology/v2/body_graph_v1.gd")
const LH = preload("res://scripts/research/ecology/v2/life_history_program_v1.gd")
const BP = preload("res://scripts/research/ecology/v2/organism_blueprint_v1.gd")
const LS = preload("res://scripts/research/ecology/v2/organism_life_state_v1.gd")
const R = preload("res://scripts/research/ecology/v2/resource_lifecycle_runtime_v1.gd")
const F = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const Field = preload("res://scripts/research/ecology/v2/local_environment_field_v1.gd")
const Fixtures = preload("res://scripts/research/ecology/v2/body_program_fixtures_v1.gd")

var passed := 0
var failed := 0

func _init() -> void:
	_development_cannot_predate_lifecycle_age()
	print("EVO_ARCH2_A5_RM20 assertions=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _check(value: bool, name: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		push_error("FAIL:" + name)

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
	policy.reproduction.maturity_ticks = 1000
	policy.reproduction.interval_ticks = 1000
	policy.reproduction.endowment = B.stock()
	policy.reproduction.fee_energy_mj = 0
	return policy

func _field() -> Dictionary:
	return Field.create("rm20.rich.field", 1, [0, 0, 0], 1000, 1, 1, F.stock(900000), F.stock(1000000), F.signals(900, 500, 0, 0))

func _encoded_state_file(blueprint: Dictionary, state: Dictionary) -> String:
	return C.encode({
		"schema": "dws.ecology.life-state-file.v1",
		"blueprint": blueprint,
		"state": state,
		"state_hash": C.digest(state),
	})

func _development_cannot_predate_lifecycle_age() -> void:
	var blueprint := BP.create(Fixtures.make(5), _policy())
	var entry := R.individual(blueprint, "rm20.organism", [500, 0, 500], B.stock(30000))
	_check(not blueprint.is_empty() and not entry.is_empty(), "development_age_entry_valid")
	if entry.is_empty(): return
	var field := _field()
	var current := entry
	for _tick in 4:
		var result := R.step_population(field, [current], field.owner_token, field.owner_epoch, field.revision)
		_check(result.success, "development_age_runtime_step_success")
		if not result.success: return
		field = result.field
		current = result.population[0]
	var state: Dictionary = current.state
	_check(LS.validate(state, blueprint).is_empty(), "reachable_development_age_state_valid")
	_check(state.development.tick <= state.age_ticks and state.development.grant_seq <= state.age_ticks, "runtime_development_counters_within_lifecycle_age")
	var causal_counter: int = maxi(int(state.development.tick), int(state.development.grant_seq))
	_check(causal_counter > 1, "witness_has_multi_tick_development_history")
	if causal_counter <= 1: return
	var impossible: Dictionary = state.duplicate(true)
	impossible.age_ticks = causal_counter - 1
	_check(LS.validate(impossible, blueprint) == "LIFE_DEVELOPMENT_CAUSALITY", "development_history_older_than_lifecycle_rejected")
	_check(LS.serialize(impossible, blueprint).is_empty(), "development_age_tamper_not_serializable")
	_check(LS.deserialize(_encoded_state_file(blueprint, impossible)).is_empty(), "development_age_tamper_deserialize_rejected")
	var text := LS.serialize(state, blueprint)
	var restored := LS.deserialize(text)
	_check(not text.is_empty() and not restored.is_empty(), "reachable_development_age_roundtrip_valid")
