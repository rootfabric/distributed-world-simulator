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
	_policy_binding_controls()
	_delayed_roundtrip_restart()
	_propagule_sequence_continuity()
	print("EVO_ARCH2_A5_RM14 assertions=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _check(value: bool, name: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		push_error("FAIL:" + name)

func _policy() -> Dictionary:
	var policy := LH.create_default()
	policy.metabolism.maintenance_energy_per_module_mj = 0
	policy.metabolism.maintenance_water_per_module_mg = 0
	policy.growth.transfer_permille = 500
	policy.growth.max_transfer = B.stock(20000)
	policy.uptake.basal_water_mg = 0
	policy.uptake.basal_nutrient_mg = 0
	policy.uptake.basal_organic_mg = 0
	policy.uptake.water_per_absorber_unit_mg = 0
	policy.uptake.nutrient_per_absorber_unit_mg = 0
	policy.uptake.organic_per_absorber_unit_mg = 0
	policy.reproduction.maturity_ticks = 4
	policy.reproduction.interval_ticks = 3
	policy.reproduction.offspring_per_event = 4
	policy.reproduction.endowment = B.stock()
	policy.reproduction.fee_energy_mj = 0
	return policy

func _reproductive_genome() -> Dictionary:
	var leaf := P.rule("leaf", [P.action("differentiate", "collector", [0, 20, 0], 1, 6000), P.action("retire")])
	var start := P.rule("start", [P.action("differentiate", "reproductive", [0, 10, 0], 1), P.action("branch", "support", [0, 0, 0], 0, 0, 0, "leaf")], "start")
	return G.create({"schema": P.SCHEMA, "entry": "start", "max_age": 12, "max_depth": 2, "rules": [start, leaf]}, "RM-A5-14 persisted reproduction witness")

func _blueprint() -> Dictionary:
	return BP.create(_reproductive_genome(), _policy())

func _entry() -> Dictionary:
	var blueprint := _blueprint()
	var entry := R.individual(blueprint, "rm14.parent", [500, 0, 500], B.stock(30000))
	if entry.is_empty(): return {}
	var field := Field.create("rm14.prepare.field", 1, [0, 0, 0], 1000, 1, 1, F.stock(900000), F.stock(1000000), F.signals(1000, 500, 0, 0))
	var prepared := R.step_population(field, [entry], field.owner_token, field.owner_epoch, field.revision)
	return prepared.population[0] if prepared.success else {}

func _encoded_state_file(blueprint: Dictionary, state: Dictionary) -> String:
	return C.encode({
		"schema": "dws.ecology.life-state-file.v1",
		"blueprint": blueprint,
		"state": state,
		"state_hash": C.digest(state),
	})

func _delayed_state(entry: Dictionary, age_tick: int = 10) -> Dictionary:
	var state: Dictionary = entry.state.duplicate(true)
	state.age_ticks = age_tick
	state.reproduction_count = 4
	state.propagule_seq = 4
	state.next_reproduction_tick = 13
	return state

func _policy_binding_controls() -> void:
	var entry := _entry()
	_check(not entry.is_empty(), "reproduction_base_entry_valid")
	if entry.is_empty(): return
	var blueprint: Dictionary = entry.blueprint
	var unaligned: Dictionary = entry.state.duplicate(true)
	unaligned.age_ticks = 20
	unaligned.reproduction_count = 1
	unaligned.propagule_seq = 1
	unaligned.next_reproduction_tick = 13
	_check(LS.validate(unaligned, blueprint) == "LIFE_REPRODUCTION_EVENT_ALIGNMENT", "offspring_count_not_multiple_of_policy_rejected")
	var premature: Dictionary = entry.state.duplicate(true)
	premature.age_ticks = 3
	premature.reproduction_count = 4
	premature.propagule_seq = 4
	premature.next_reproduction_tick = 7
	_check(not LS.validate(premature, blueprint).is_empty(), "reproduction_before_maturity_rejected")
	var no_events_wrong_schedule: Dictionary = entry.state.duplicate(true)
	no_events_wrong_schedule.age_ticks = 10
	no_events_wrong_schedule.next_reproduction_tick = 5
	_check(LS.validate(no_events_wrong_schedule, blueprint) == "LIFE_REPRODUCTION_SCHEDULE", "zero_events_schedule_must_equal_maturity")
	var too_close: Dictionary = entry.state.duplicate(true)
	too_close.age_ticks = 6
	too_close.reproduction_count = 8
	too_close.propagule_seq = 8
	too_close.next_reproduction_tick = 9
	_check(not LS.validate(too_close, blueprint).is_empty(), "two_events_closer_than_interval_rejected")
	var delayed := _delayed_state(entry, 10)
	_check(LS.validate(delayed, blueprint).is_empty(), "delayed_physically_possible_reproduction_accepted")
	var delayed_two: Dictionary = entry.state.duplicate(true)
	delayed_two.age_ticks = 13
	delayed_two.reproduction_count = 8
	delayed_two.propagule_seq = 8
	delayed_two.next_reproduction_tick = 16
	_check(LS.validate(delayed_two, blueprint).is_empty(), "multiple_delayed_events_with_interval_possible")
	_check(LS.serialize(unaligned, blueprint).is_empty(), "unaligned_state_not_serializable")
	_check(LS.deserialize(_encoded_state_file(blueprint, unaligned)).is_empty(), "unaligned_state_deserialize_rejected")

func _delayed_roundtrip_restart() -> void:
	var entry := _entry()
	if entry.is_empty(): return
	var blueprint: Dictionary = entry.blueprint
	var delayed := _delayed_state(entry, 10)
	var text := LS.serialize(delayed, blueprint)
	_check(not text.is_empty(), "delayed_state_serializes")
	var restored := LS.deserialize(text)
	_check(not restored.is_empty() and LS.state_hash(restored.state, restored.blueprint) == LS.state_hash(delayed, blueprint), "delayed_state_roundtrip_exact")
	if restored.is_empty(): return
	var field := Field.create("rm14.restart.field", 1, [0, 0, 0], 1000, 1, 1, F.stock(), F.stock(1000000), F.signals(0, 500, 0, 0))
	var restarted := R.step_population(field, [{"blueprint": restored.blueprint, "state": restored.state}], field.owner_token, field.owner_epoch, field.revision)
	_check(restarted.success, "delayed_state_restart_step_success")
	if not restarted.success: return
	var state: Dictionary = restarted.population[0].state
	_check(state.age_ticks == 11 and state.reproduction_count == 4 and state.propagule_seq == 4 and state.next_reproduction_tick == 13, "delayed_restart_preserves_schedule_until_due")
	_check(LS.validate(state, blueprint).is_empty(), "delayed_restart_state_valid")

func _propagule_sequence_continuity() -> void:
	var entry := _entry()
	if entry.is_empty(): return
	var blueprint: Dictionary = entry.blueprint
	var ready := _delayed_state(entry, 13)
	ready.next_reproduction_tick = 13
	_check(LS.validate(ready, blueprint).is_empty(), "sequence_source_state_valid")
	var reproduced := R._reproduce(ready, blueprint, blueprint.life_history)
	_check(reproduced.success, "second_delayed_reproduction_success")
	if not reproduced.success: return
	_check(reproduced.state.reproduction_count == 8 and reproduced.state.propagule_seq == 8 and reproduced.state.next_reproduction_tick == 16, "second_event_updates_policy_bound_counters")
	_check(reproduced.propagules.size() == 4, "policy_offspring_per_event_emitted")
	var sequences: Array = []
	var identities_valid := true
	for propagule in reproduced.propagules:
		sequences.append(propagule.sequence)
		identities_valid = identities_valid and propagule.id == R._propagule_id(ready.individual_id, propagule.sequence)
		identities_valid = identities_valid and R.validate_propagule(propagule, blueprint).is_empty()
	_check(sequences == [4, 5, 6, 7], "propagule_sequence_continues_from_persisted_counter")
	_check(identities_valid, "canonical_seed_ids_follow_continued_sequence")
	_check(LS.validate(reproduced.state, blueprint).is_empty(), "post_reproduction_policy_state_valid")
