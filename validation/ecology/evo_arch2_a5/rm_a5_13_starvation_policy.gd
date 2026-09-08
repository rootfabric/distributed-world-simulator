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
	_policy_binding_controls()
	_roundtrip_and_restart()
	print("EVO_ARCH2_A5_RM13 assertions=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _check(value: bool, name: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		push_error("FAIL:" + name)

func _policy() -> Dictionary:
	var policy := LH.create_default()
	policy.survival.starvation_limit_ticks = 3
	policy.metabolism.maintenance_energy_per_module_mj = 0
	policy.metabolism.maintenance_water_per_module_mg = 0
	policy.growth.transfer_permille = 0
	return policy

func _blueprint() -> Dictionary:
	return BP.create(Fixtures.make(0), _policy())

func _entry() -> Dictionary:
	var blueprint := _blueprint()
	return R.individual(blueprint, "rm13.parent", [500, 0, 500], B.stock())

func _encoded_state_file(blueprint: Dictionary, state: Dictionary) -> String:
	return C.encode({
		"schema": "dws.ecology.life-state-file.v1",
		"blueprint": blueprint,
		"state": state,
		"state_hash": C.digest(state),
	})

func _policy_binding_controls() -> void:
	var entry := _entry()
	_check(not entry.is_empty(), "starvation_base_entry_valid")
	if entry.is_empty(): return
	var blueprint: Dictionary = entry.blueprint
	var dead_zero: Dictionary = entry.state.duplicate(true)
	dead_zero.alive = false
	dead_zero.starvation_ticks = 0
	_check(LS.validate(dead_zero, blueprint) == "LIFE_STARVATION_POLICY", "dead_zero_starvation_rejected")
	var alive_limit: Dictionary = entry.state.duplicate(true)
	alive_limit.age_ticks = 3
	alive_limit.starvation_ticks = 3
	_check(LS.validate(alive_limit, blueprint) == "LIFE_STARVATION_POLICY", "alive_at_limit_rejected")
	var dead_limit: Dictionary = entry.state.duplicate(true)
	dead_limit.age_ticks = 3
	dead_limit.alive = false
	dead_limit.starvation_ticks = 3
	_check(LS.validate(dead_limit, blueprint).is_empty(), "dead_at_exact_limit_accepted")
	var temporal: Dictionary = entry.state.duplicate(true)
	temporal.age_ticks = 1
	temporal.starvation_ticks = 2
	_check(LS.validate(temporal, blueprint) == "LIFE_STARVATION_CAUSALITY", "starvation_cannot_exceed_age")
	_check(LS.serialize(dead_zero, blueprint).is_empty(), "invalid_dead_state_not_serializable")
	_check(LS.deserialize(_encoded_state_file(blueprint, dead_zero)).is_empty(), "invalid_dead_state_deserialize_rejected")

func _roundtrip_and_restart() -> void:
	var entry := _entry()
	if entry.is_empty(): return
	var blueprint: Dictionary = entry.blueprint
	var dead_limit: Dictionary = entry.state.duplicate(true)
	dead_limit.age_ticks = 3
	dead_limit.alive = false
	dead_limit.starvation_ticks = 3
	var text := LS.serialize(dead_limit, blueprint)
	_check(not text.is_empty(), "dead_limit_serializes")
	var restored := LS.deserialize(text)
	_check(not restored.is_empty() and LS.state_hash(restored.state, restored.blueprint) == LS.state_hash(dead_limit, blueprint), "dead_limit_roundtrip_exact")
	if restored.is_empty(): return
	var field := Field.create("rm13.restart.field", 1, [0, 0, 0], 1000, 1, 1, F.stock(900000), F.stock(1000000), F.signals(1000, 500, 0, 0))
	var restarted := R.step_population(field, [{"blueprint": restored.blueprint, "state": restored.state}], field.owner_token, field.owner_epoch, field.revision)
	_check(restarted.success, "dead_limit_restart_step_success")
	if not restarted.success: return
	var state: Dictionary = restarted.population[0].state
	_check(not state.alive and state.starvation_ticks == 3 and state.age_ticks == 3, "dead_limit_restart_stays_inert")
	_check(state.resource_ledger.field_intake == dead_limit.resource_ledger.field_intake, "dead_limit_restart_has_no_intake")
	_check(LS.validate(state, blueprint).is_empty(), "dead_limit_restart_state_valid")
