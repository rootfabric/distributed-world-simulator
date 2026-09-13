extends SceneTree
const X = preload("res://tests/research/ecology/v2/arch2_a6_fixtures.gd")
const C = X.C
const B = X.B
const LS = X.LS
const R = X.R
const F = X.F
const A6 = X.A6
var passed := 0
var failed := 0

func _init() -> void:
	_empty_abiotic()
	_death_inventory_and_exhaustion()
	_paid_body_and_closed_loop()
	_capacity_and_order()
	_spatial_locality()
	_propague_outbox()
	_restart_and_rollback()
	print("EVO_ARCH2_A6_EXACT assertions=%d failed=%d" % [passed + failed, failed])
	quit(0 if failed == 0 else 1)

func _check(value: bool, name: String) -> void:
	if value: passed += 1
	else: failed += 1; push_error("FAIL:" + name)

func _empty_abiotic() -> void:
	var p := A6.default_policy()
	p.mineralization_per_cell_mg = 3
	var f := X.field({"water_mg": 7, "nutrient_mg": 2, "organic_mg": 10}, 20)
	var before := C.digest(f)
	var made := A6.create("empty", f, [], p)
	_check(made.success, "empty_session_allowed")
	if not made.success: return
	_check(C.digest(f) == before, "create_does_not_mutate_field")
	var first := X.step(made.state)
	_check(first.success, "empty_session_advances")
	if not first.success: return
	var s: Dictionary = first.state
	_check(s.frame.field.tick == 1 and s.frame.step == 1, "abiotic_clock_advances_without_life")
	_check(s.frame.field.cells[0].stocks == {"water_mg": 7, "nutrient_mg": 5, "organic_mg": 7}, "mineralization_exact_stocks")
	_check(s.frame.field.ledger.inputs.nutrient_mg == 3 and s.frame.field.ledger.sinks.organic_mg == 3, "mineralization_exact_a4_ledgers")
	_check(s.frame.mineralized_mg == 3 and F.validate_state(s.frame.field).is_empty(), "mineralization_preserves_a4_contract")
	var accounts := A6.balance(s)
	_check(accounts.initial.material_mg == 12 and accounts.current.material_mg == 12, "empty_abiotic_material_conserved")
	var second := X.step(s)
	_check(second.success and second.state.frame.field.cells[0].stocks.organic_mg == 4, "abiotic_continues_after_empty_step")
	var zero := A6.default_policy()
	zero.mineralization_per_cell_mg = 0
	var no_op := A6.create("zero.rate", f, [], zero)
	var tick := X.step(no_op.state)
	_check(tick.success and tick.state.frame.field.cells[0].stocks == f.cells[0].stocks and tick.state.frame.field.tick == 1, "zero_rates_are_explicit_not_empty_field")

func _death_inventory_and_exhaustion() -> void:
	var p := A6.default_policy()
	p.material_return_mg = 7; p.water_return_mg = 3; p.energy_dissipation_mj = 5; p.mineralization_per_cell_mg = 4
	var donor := X.root("donor", X.stock(17, 9, 11), true)
	var made := A6.create("death", X.field(), [donor], p)
	_check(made.success, "death_witness_created")
	if not made.success: return
	var first := X.step(made.state)
	_check(first.success, "death_and_return_atomic_step")
	if not first.success: return
	var s: Dictionary = first.state
	var dead := X.entry(s, "donor")
	_check(not dead.state.alive and dead.state.starvation_ticks == 1, "real_a5_starvation_death")
	_check(s.frame.corpses.size() == 1 and s.frame.corpses[0].death_step == 1, "single_corpse_registered_at_death")
	var corpse: Dictionary = s.frame.corpses[0]
	_check(corpse.inventory == X.stock(17, 9, 11) and corpse.remaining == X.stock(10, 6, 6), "exact_corpse_inventory_and_remaining")
	_check(corpse.source_hash == C.digest(dead.state), "corpse_bound_to_frozen_a5_snapshot")
	_check(corpse.returned == {"water_mg": 3, "nutrient_mg": 0, "organic_mg": 7}, "exact_return_channels")
	_check(s.frame.dissipated_energy_mj == 5 and s.frame.field.cells[0].stocks.nutrient_mg == 4, "explicit_heat_sink_and_material_conversion")
	var frozen := C.digest(dead)
	for _i in 2:
		var next := X.step(s)
		_check(next.success, "decomposition_continues_after_extinction")
		if not next.success: return
		s = next.state
	_check(s.frame.corpses.size() == 1 and s.frame.corpses[0].remaining == B.stock(), "corpse_exhausts_without_duplicate_inventory")
	_check(s.frame.returned.organic_mg == 17 and s.frame.returned.water_mg == 9 and s.frame.dissipated_energy_mj == 11, "all_and_only_available_resources_transferred")
	_check(C.digest(X.entry(s, "donor")) == frozen, "dead_witness_remains_immutable")
	for _i in 3:
		var next := X.step(s)
		_check(next.success, "abiotic_continues_after_corpse_exhaustion")
		if not next.success: return
		s = next.state
	_check(s.frame.field.cells[0].stocks == {"water_mg": 9, "nutrient_mg": 17, "organic_mg": 0}, "final_closed_resource_cycle")
	_check(s.frame.returned.organic_mg == 17 and s.frame.corpses.size() == 1, "exhausted_corpse_never_redeposits")
	var account := A6.balance(s)
	_check(account.current == X.stock(17, 9, 0) and account.sinks == X.stock(0, 0, 11), "archive_not_counted_as_second_spendable_inventory")
	print("A6_EXTINCTION_WITNESS ", C.encode({"step": s.frame.step, "returned": s.frame.returned, "heat": s.frame.dissipated_energy_mj, "stocks": s.frame.field.cells[0].stocks}))

func _paid_body_and_closed_loop() -> void:
	var donor := X.prepared_donor()
	_check(not donor.is_empty(), "donor_grows_and_reproduces_through_real_a5")
	if donor.is_empty(): return
	_check(donor.state.development.modules.size() == 2 and donor.state.reproduction_count == 1, "real_paid_body_and_reproduction_present")
	var p := A6.default_policy()
	var made := A6.create("closed.loop", X.field(), [donor, X.recipient()], p)
	var off := p.duplicate(true); off.decomposition_enabled = false
	var control := A6.create("closed.loop", X.field(), [donor, X.recipient()], off)
	_check(made.success and control.success, "paired_feedback_experiment_created")
	if not made.success or not control.success: return
	var live := X.step(made.state)
	var inert := X.step(control.state)
	_check(live.success and inert.success, "paired_death_steps_valid")
	if not live.success or not inert.success: return
	var corpse: Dictionary = live.state.frame.corpses[0]
	var d := X.entry(live.state, "donor")
	var material: int = d.state.metabolic_reserves.material_mg + d.state.development.reserves.material_mg + d.state.development.modules[1].cost.material_mg
	var water: int = d.state.metabolic_reserves.water_mg + d.state.development.reserves.water_mg
	var energy: int = d.state.metabolic_reserves.energy_mj + d.state.development.reserves.energy_mj
	_check(corpse.inventory == X.stock(material, water, energy), "paid_body_material_plus_unspent_reserves_exact")
	_check(d.state.development.spent.water_mg > 0 and corpse.inventory.water_mg < d.state.metabolic_reserves.water_mg + d.state.development.received.water_mg, "spent_construction_water_not_recycled")
	_check(d.state.development.spent.energy_mj > 0 and corpse.inventory.energy_mj < d.state.metabolic_reserves.energy_mj + d.state.development.received.energy_mj, "spent_construction_energy_not_recycled")
	_check(X.entry(live.state, "recipient").state.resource_ledger.field_intake.nutrient_mg == 0, "recipient_cannot_consume_future_return")
	_check(inert.state.frame.returned == F.stock() and inert.state.frame.corpses[0].remaining == corpse.inventory, "effects_off_retains_all_corpse_resources")
	var next := X.step(live.state)
	var control_next := X.step(inert.state)
	_check(next.success and control_next.success, "recipient_feedback_step_succeeds")
	if not next.success or not control_next.success: return
	var recipient := X.entry(next.state, "recipient")
	var control_recipient := X.entry(control_next.state, "recipient")
	_check(recipient.state.resource_ledger.field_intake.nutrient_mg == 100, "recipient_consumes_actual_returned_nutrient")
	_check(control_recipient.state.resource_ledger.field_intake.nutrient_mg == 0, "effects_off_counterfactual_has_no_free_nutrient")
	_check(recipient.state.metabolic_reserves.material_mg == 100 and control_recipient.state.metabolic_reserves.material_mg == 0, "persistent_environment_has_causal_biological_effect")
	_check(A6.validate(next.state).is_empty() and A6.validate(control_next.state).is_empty(), "both_counterfactual_histories_replay")
	print("A6_NICHE_WITNESS ", C.encode({"feedback_intake_mg": recipient.state.resource_ledger.field_intake.nutrient_mg, "effects_off_intake_mg": control_recipient.state.resource_ledger.field_intake.nutrient_mg, "body_modules": d.state.development.modules.size()}))

func _capacity_and_order() -> void:
	var p := A6.default_policy(); p.mineralization_per_cell_mg = 3
	var f := X.field({"water_mg": 0, "nutrient_mg": 0, "organic_mg": 5}, 5)
	var a := X.root("a", X.stock(10, 0, 0), true)
	var b := X.root("b", X.stock(20, 0, 0), true)
	var one := A6.create("capacity", f, [b, a], p)
	var two := A6.create("capacity", f, [a, b], p)
	_check(one.success and two.success and one.state == two.state, "input_permutation_same_genesis")
	if not one.success or not two.success: return
	var s: Dictionary = one.state
	var t: Dictionary = two.state
	for i in 3:
		var next := X.step(s); var peer := X.step(t)
		_check(next.success and peer.success and next.state == peer.state, "competing_returns_order_independent")
		if not next.success or not peer.success: return
		s = next.state; t = peer.state
		if i == 0:
			_check(s.frame.returned.organic_mg == 0 and s.frame.corpses[0].remaining.material_mg == 10, "full_capacity_defers_return_without_loss")
		if i == 1:
			_check(s.frame.corpses[0].returned.organic_mg == 3 and s.frame.corpses[1].returned.organic_mg == 0, "canonical_id_capacity_reservation")
	_check(s.frame.field.cells[0].stocks.organic_mg == 5 and s.frame.field.cells[0].stocks.nutrient_mg == 5, "nutrient_capacity_bounds_mineralization")
	_check(s.frame.corpses[0].remaining.material_mg == 5 and s.frame.corpses[1].remaining.material_mg == 20, "unreleased_corpse_material_retained")
	_check(s.frame.mineralized_mg == 5 and A6.balance(s).current.material_mg == 35, "capacity_saturation_global_material_conservation")

func _spatial_locality() -> void:
	var f := X.field(F.stock(), 100, [-1000, 0, -1000], 2)
	var donor := X.root("negative.position", X.stock(10, 0, 0), true, [-500, 0, -500])
	var made := A6.create("spatial", f, [donor], A6.default_policy())
	_check(made.success, "negative_coordinate_patch_valid")
	if not made.success: return
	var next := X.step(made.state)
	_check(next.success and next.state.frame.field.cells[0].stocks.nutrient_mg == 10, "return_targets_exact_anchor_cell")
	_check(next.success and next.state.frame.field.cells[1].stocks == F.stock(), "unrelated_cell_unchanged")
	var outside := X.root("outside", B.stock(), false, [1000, 0, -500])
	var bad := A6.create("outside", f, [outside], A6.default_policy())
	_check(not bad.success and bad.error == "A6_POSITION", "half_open_upper_boundary_rejected")

func _propague_outbox() -> void:
	var made := A6.create("reproduction", X.field(F.stock(5000), 5000), [X.reproductive()], A6.default_policy())
	_check(made.success, "paid_outbox_session_created")
	if not made.success: return
	var first := X.step(made.state)
	_check(first.success and first.state.frame.propagules.size() == 1, "real_paid_propagule_preserved")
	if not first.success or first.state.frame.propagules.is_empty(): return
	var receipt: Dictionary = first.state.frame.propagules[0]
	var parent := LS.deserialize(receipt.parent_payload)
	_check(not parent.is_empty() and R.validate_propagule(receipt.propagule, parent.blueprint, parent.state).is_empty(), "outbox_exact_paid_parent_witness")
	_check(not R.materialize_propagule(receipt.propagule, parent.blueprint, parent.state).is_empty(), "outbox_seed_is_materializable_by_existing_a5")
	var second := X.step(first.state)
	_check(second.success and second.state.frame.propagules.size() == 1 and second.state.frame.corpses.size() == 1, "parent_death_does_not_erase_paid_seed")
	_check(second.success and A6.validate(second.state).is_empty(), "body_corpse_outbox_conserve_together")
	var text := A6.serialize(second.state)
	var restored := A6.deserialize(text, second.state.genesis_hash, second.state.frame.step)
	_check(not restored.is_empty() and restored.frame.propagules == second.state.frame.propagules, "paid_outbox_restart_exact")

func _restart_and_rollback() -> void:
	var p := A6.default_policy(); p.material_return_mg = 7; p.mineralization_per_cell_mg = 4
	var made := A6.create("restart", X.field(), [X.root("donor", X.stock(50, 9, 20), true)], p)
	_check(made.success, "restart_session_created")
	if not made.success: return
	var s: Dictionary = made.state
	for _i in 3:
		var next := X.step(s)
		_check(next.success, "restart_prefix_step")
		if not next.success: return
		s = next.state
	var saved := A6.serialize(s)
	var loaded := A6.deserialize(saved, s.genesis_hash, s.frame.step)
	_check(not saved.is_empty() and loaded == s and A6.serialize(loaded) == saved, "canonical_consistent_cut_roundtrip")
	var before := C.digest(s)
	for kind in 3:
		var wrong := A6.advance(s, "wrong" if kind == 0 else s.frame.field.owner_token, 9 if kind == 1 else s.frame.field.owner_epoch, 0 if kind == 2 else s.frame.step)
		_check(not wrong.success and wrong.error == ["STALE_OWNER", "STALE_OWNER_EPOCH", "STALE_REVISION"][kind], "stale_write_fence")
	_check(C.digest(s) == before, "failed_write_is_mutation_free")
	var uninterrupted := X.step(s)
	var resumed := X.step(loaded)
	_check(uninterrupted.success and resumed.success and uninterrupted.state == resumed.state, "restart_next_step_byte_exact")
	var duplicate := A6.advance(uninterrupted.state, s.frame.field.owner_token, s.frame.field.owner_epoch, s.frame.step)
	_check(not duplicate.success and duplicate.error == "STALE_REVISION", "duplicate_committed_step_rejected")
	_check(A6.deserialize(saved, "f".repeat(64), s.frame.step).is_empty(), "foreign_genesis_anchor_rejected")
	_check(A6.deserialize(saved, s.genesis_hash, s.frame.step + 1).is_empty(), "stale_snapshot_revision_rejected")
	_check(A6.deserialize(saved, "", s.frame.step).is_empty(), "missing_external_anchor_rejected")
