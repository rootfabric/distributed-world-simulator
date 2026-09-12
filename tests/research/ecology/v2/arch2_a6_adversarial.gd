extends SceneTree
const X = preload("res://tests/research/ecology/v2/arch2_a6_fixtures.gd")
const C = X.C
const B = X.B
const F = X.F
const LS = X.LS
const A6 = X.A6
var passed := 0
var failed := 0

func _init() -> void:
	_coherent_forgery()
	_strict_input()
	_revision_and_tick_rollback()
	_outbox_budget()
	_horizon_budget()
	print("EVO_ARCH2_A6_ADVERSARIAL assertions=%d failed=%d" % [passed + failed, failed])
	quit(0 if failed == 0 else 1)

func _check(value: bool, name: String) -> void:
	if value: passed += 1
	else: failed += 1; push_error("FAIL:" + name)

func _witness() -> Dictionary:
	var p := A6.default_policy()
	p.material_return_mg = 7; p.water_return_mg = 3; p.energy_dissipation_mj = 5
	p.mineralization_enabled = false
	var made := A6.create("adversarial", X.field(), [X.root("donor", X.stock(30, 9, 20), true)], p)
	if not made.success: return {}
	var step := X.step(made.state)
	return step.state if step.success else {}

func _rejected_forge(v: Dictionary, original: Dictionary, name: String) -> void:
	var sealed := X.reseal(v)
	_check(A6.validate(sealed) == "A6_REPLAY_MISMATCH", name + "_replay")
	_check(A6.serialize(sealed).is_empty(), name + "_serialize")
	_check(A6.deserialize(C.encode(sealed), original.genesis_hash, original.frame.step).is_empty(), name + "_deserialize")
	var run := X.step(sealed)
	_check(not run.success and not run.has("state"), name + "_runtime_admission")

func _coherent_forgery() -> void:
	var s := _witness()
	_check(not s.is_empty() and A6.validate(s).is_empty(), "genuine_adversarial_base_valid")
	if s.is_empty(): return
	var refund := s.duplicate(true)
	refund.frame.corpses[0].remaining.material_mg += 1
	refund.frame.corpses[0].returned.organic_mg -= 1
	refund.frame.returned.organic_mg -= 1
	refund.frame.field.cells[0].stocks.organic_mg -= 1
	refund.frame.field.ledger.inputs.organic_mg -= 1
	refund.frame.field = X.Field._seal_mutated_state(refund.frame.field)
	_check(F.validate_state(refund.frame.field).is_empty(), "coherent_refund_preserves_a4_integrity")
	_check(A6._balance_error(refund.genesis, refund.frame).is_empty(), "coherent_refund_preserves_global_conservation")
	_rejected_forge(refund, s, "coherent_corpse_refund")

	var heat := s.duplicate(true)
	heat.frame.corpses[0].remaining.energy_mj += 1
	heat.frame.corpses[0].dissipated_energy_mj -= 1
	heat.frame.dissipated_energy_mj -= 1
	_check(A6._balance_error(heat.genesis, heat.frame).is_empty(), "heat_refund_preserves_global_conservation")
	_rejected_forge(heat, s, "coherent_heat_refund")

	var temporal := s.duplicate(true)
	temporal.frame.corpses[0].death_step = 0
	_rejected_forge(temporal, s, "forged_death_timing")

	var marker := s.duplicate(true)
	var dead := LS.deserialize(marker.frame.population[0])
	dead.state.development.last_events = [{"tip": "p000000", "rule": "start", "outcome": "MODULE_CREATED"}]
	_check(LS.validate(dead.state, dead.blueprint).is_empty(), "syntactic_module_event_still_passes_frozen_a5")
	marker.frame.population[0] = LS.serialize(dead.state, dead.blueprint)
	marker.frame.corpses[0].source_hash = C.digest(dead.state)
	_rejected_forge(marker, s, "coherent_dead_source_marker")

	var inflation := s.duplicate(true)
	inflation.frame.field.cells[0].stocks.nutrient_mg += 1
	inflation.frame.field.ledger.inputs.nutrient_mg += 1
	inflation.frame.field = X.Field._seal_mutated_state(inflation.frame.field)
	_check(F.validate_state(inflation.frame.field).is_empty(), "self_asserted_field_input_locally_valid")
	_rejected_forge(inflation, s, "unfunded_field_input")

	var duplicate := s.duplicate(true)
	duplicate.frame.corpses.append(duplicate.frame.corpses[0].duplicate(true))
	_rejected_forge(duplicate, s, "duplicate_corpse")
	var erased := s.duplicate(true); erased.frame.corpses = []
	_rejected_forge(erased, s, "erased_corpse")
	var clock := s.duplicate(true)
	clock.frame.field.tick += 1
	clock.frame.field = X.Field._seal_mutated_state(clock.frame.field)
	_rejected_forge(clock, s, "independent_field_clock_splice")
	_check(not A6.deserialize(A6.serialize(s), s.genesis_hash, s.frame.step).is_empty(), "untampered_positive_control_roundtrip")

func _strict_input() -> void:
	var s := _witness()
	if s.is_empty(): _check(false, "strict_input_base"); return
	var unknown := s.duplicate(true); unknown["extra"] = 0
	_check(A6.validate(X.reseal(unknown)) == "A6_SCHEMA", "unknown_snapshot_fields_rejected")
	var extra_frame := s.duplicate(true); extra_frame.frame["extra"] = 0
	_check(A6.validate(X.reseal(extra_frame)) == "A6_FRAME_SCHEMA", "unknown_frame_fields_rejected")
	var unsealed := s.duplicate(true); unsealed.frame.returned.organic_mg += 1
	_check(A6.validate(unsealed) == "A6_INTEGRITY_HASH", "unsealed_snapshot_tamper_rejected")
	var fp := s.duplicate(true); fp.frame.step = 1.0
	_check(not A6.validate(X.reseal(fp)).is_empty(), "float_step_rejected")
	var wrong_genesis := s.duplicate(true); wrong_genesis.genesis.field = 123
	wrong_genesis.genesis_hash = C.digest(wrong_genesis.genesis)
	_check(A6.validate(X.reseal(wrong_genesis)) == "A6_GENESIS_FIELD", "malformed_genesis_fails_without_crash")
	for value in [-1, F.MAX_REQUEST + 1, 1.5, "10"]:
		var p := A6.default_policy(); p.material_return_mg = value
		_check(not A6.create("invalid.policy", X.field(), [], p).success, "invalid_rate_rejected")
	var flags := A6.default_policy(); flags.decomposition_enabled = 1
	_check(A6.validate_policy(flags) == "A6_POLICY_FLAGS", "nonboolean_flag_rejected")
	var extras := A6.default_policy(); extras["free_energy"] = true
	_check(A6.validate_policy(extras) == "A6_POLICY_SCHEMA", "unknown_policy_field_rejected")
	var person := X.root("same", B.stock())
	var duplicate := A6.create("duplicate", X.field(), [person, person], A6.default_policy())
	_check(not duplicate.success and duplicate.error == "A6_DUPLICATE_INDIVIDUAL", "duplicate_genesis_identity_rejected")
	var too_many: Array = []
	for i in A6.MAX_POPULATION + 1: too_many.append(X.root("root.%d" % i, B.stock()))
	_check(not A6.create("population.budget", X.field(), too_many, A6.default_policy()).success, "population_budget_explicit")
	var too_wide := X.Field.create("patch", 1, [0, 0, 0], 1000, 9, 8, F.stock(), F.stock(100))
	_check(not A6.create("cells.budget", too_wide, [], A6.default_policy()).success, "field_cell_budget_explicit")
	var huge := "x".repeat(C.MAX_BYTES + 1)
	_check(A6.deserialize(huge, s.genesis_hash, s.frame.step).is_empty(), "oversize_input_rejected_before_parse")
	_check(A6.deserialize("{", s.genesis_hash, s.frame.step).is_empty(), "truncated_snapshot_rejected")
	var nested := "[".repeat(26) + "0" + "]".repeat(26)
	_check(A6.deserialize(nested, s.genesis_hash, s.frame.step).is_empty(), "excessive_nesting_rejected")
	var spoof := s.duplicate(true)
	spoof.genesis.population = [huge]
	spoof.genesis_hash = C.digest(spoof.genesis)
	_check(A6.validate(X.reseal(spoof)) == "A6_SNAPSHOT_BUDGET", "envelope_byte_budget_explicit")
	var alternative := A6.create("another.genesis", X.field(), [], A6.default_policy())
	_check(alternative.success and A6.deserialize(A6.serialize(alternative.state), s.genesis_hash, 0).is_empty(), "valid_foreign_experiment_cannot_replace_anchor")

func _revision_and_tick_rollback() -> void:
	for kind in 2:
		var field := X.field()
		if kind == 0: field.revision = F.MAX_REVISION - 1
		else: field.tick = F.MAX_TICK
		field = X.Field._seal_mutated_state(field)
		var made := A6.create("rollback.%d" % kind, field, [X.root("donor", X.stock(30, 0, 20), true)], A6.default_policy())
		_check(made.success, "near_limit_field_is_valid_initial_fixture")
		if not made.success: continue
		var before := C.digest(made.state)
		var next := X.step(made.state)
		_check(not next.success and not next.has("state"), "later_field_failure_rejects_whole_transition")
		_check(C.digest(made.state) == before and made.state.frame.corpses.is_empty(), "failed_return_retains_original_life_and_field")
		_check(X.entry(made.state, "donor").state.alive, "failed_transaction_cannot_partially_kill_donor")

func _outbox_budget() -> void:
	var p := X.policy()
	p.growth.transfer_permille = 500; p.growth.max_transfer = B.stock(1000)
	p.reproduction.maturity_ticks = 1; p.reproduction.interval_ticks = 1
	p.reproduction.offspring_per_event = 4; p.reproduction.endowment = B.stock(); p.reproduction.fee_energy_mj = 0
	var blueprint := X.BP.create(X.genome(true), p)
	var population: Array = []
	for i in A6.MAX_POPULATION:
		population.append(X.R.individual(blueprint, "storm.%02d" % i, [500, 0, 500], B.stock(10000)))
	var made := A6.create("outbox.budget", X.field(F.stock(1000), 1000), population, A6.default_policy())
	_check(made.success, "bounded_seed_storm_created")
	if not made.success: return
	var first := X.step(made.state)
	_check(first.success and first.state.frame.propagules.size() == A6.MAX_PROPAGULES, "outbox_exact_capacity_is_valid")
	if not first.success: return
	var before := C.digest(first.state)
	var overflow := X.step(first.state)
	_check(not overflow.success and overflow.error == "A6_PROPAGULE_BUDGET" and not overflow.has("state"), "outbox_overflow_not_silent_seed_loss")
	_check(C.digest(first.state) == before, "outbox_overflow_does_not_debit_parent")
	var replay_limit: Dictionary = made.state.duplicate(true)
	replay_limit.frame.step = 17
	_check(A6.validate(X.reseal(replay_limit)) == "A6_REPLAY_WORK_BUDGET", "replay_work_limit_checked_before_expensive_history")
	var duplicate_seed: Dictionary = first.state.duplicate(true)
	duplicate_seed.frame.propagules[1] = duplicate_seed.frame.propagules[0].duplicate(true)
	_check(A6.validate(X.reseal(duplicate_seed)) == "A6_REPLAY_MISMATCH", "duplicate_paid_seed_receipt_rejected")
	var altered_seed: Dictionary = first.state.duplicate(true)
	altered_seed.frame.propagules[0].propagule.endowment.material_mg += 1
	_check(A6.validate(X.reseal(altered_seed)) == "A6_REPLAY_MISMATCH", "unpaid_outbox_endowment_rejected")

func _horizon_budget() -> void:
	var made := A6.create("horizon", X.field(), [], A6.default_policy())
	var s: Dictionary = made.state
	var all_ok := true
	for _i in A6.MAX_STEPS:
		var next := X.step(s)
		if not next.success:
			all_ok = false
			break
		s = next.state
	_check(all_ok and s.frame.step == A6.MAX_STEPS, "last_permitted_replay_step_is_real")
	var before := C.digest(s)
	var extra := X.step(s)
	_check(not extra.success and extra.error == "A6_STEP_BUDGET", "horizon_exhaustion_is_explicit_budget_error")
	_check(C.digest(s) == before and F.validate_state(s.frame.field).is_empty(), "horizon_error_preserves_final_valid_snapshot")
