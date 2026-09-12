extends SceneTree
const X = preload("res://tests/research/ecology/v2/arch2_a6_fixtures.gd")
const A6 = X.A6
var good := true

func check(v: bool, label: String) -> void:
	good = good and v
	if not v: push_error("FAIL:" + label)

func _init() -> void:
	var on_policy := A6.default_policy()
	var off_policy := on_policy.duplicate(true); off_policy.decomposition_enabled = false
	var pop := [X.reproductive(), X.recipient()]
	var f := X.field(X.F.stock(5000), 5000)
	var a := A6.create("complete.cycle", f, pop, on_policy)
	var b := A6.create("complete.cycle", f, pop, off_policy)
	check(a.success and b.success, "genesis")
	if not good: quit(1); return
	var first := X.step(a.state); var first_off := X.step(b.state)
	check(first.success and first_off.success, "first_step")
	if not good: quit(1); return
	var donor := X.entry(first.state, "donor")
	check(donor.state.development.modules.size() == 2 and donor.state.reproduction_count == 1, "same_session_paid_growth_reproduction")
	check(first.state.frame.propagules.size() == 1 and first.state.frame.field.cells[0].stocks == X.F.stock(), "same_field_fully_consumed")
	var second := X.step(first.state); var second_off := X.step(first_off.state)
	check(second.success and second_off.success, "second_step")
	if not good: quit(1); return
	check(not X.entry(second.state, "donor").state.alive and second.state.frame.corpses.size() == 1, "same_session_real_death")
	check(second.state.frame.field.cells[0].stocks.nutrient_mg == 1000 and second_off.state.frame.field.cells[0].stocks.nutrient_mg == 0, "same_field_replenished_only_by_corpse")
	var cut := A6.deserialize(A6.serialize(second.state), second.state.genesis_hash, second.state.frame.step)
	var third := X.step(second.state); var third_off := X.step(second_off.state); var restored := X.step(cut)
	check(third.success and third_off.success and restored.success, "third_step")
	if not good: quit(1); return
	var baseline: int = X.entry(first.state, "recipient").state.resource_ledger.field_intake.nutrient_mg
	var with_feedback: int = X.entry(third.state, "recipient").state.resource_ledger.field_intake.nutrient_mg - baseline
	var without_feedback: int = X.entry(third_off.state, "recipient").state.resource_ledger.field_intake.nutrient_mg - baseline
	check(with_feedback == 100 and without_feedback == 0, "closed_loop_delta")
	check(third.state == restored.state, "full_cycle_restart")
	check(A6.validate(third.state).is_empty() and not A6.balance(third.state).has("error"), "full_cycle_conservation")
	print("A6_FULL_CYCLE ", X.C.encode({"initial_recipient_uptake": baseline, "feedback_delta_mg": with_feedback, "control_delta_mg": without_feedback, "reproduction_count": donor.state.reproduction_count, "body_modules": donor.state.development.modules.size(), "checkpoint_step": third.state.frame.step, "restart_equal": third.state == restored.state, "pass": good}))
	quit(0 if good else 1)
