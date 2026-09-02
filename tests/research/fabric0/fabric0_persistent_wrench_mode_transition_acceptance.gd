extends SceneTree

const L = preload("res://scripts/research/fabric0/fabric0_persistent_wrench_mode_event_locator_v1.gd")
const E = preload("res://scripts/research/fabric0/fabric0_persistent_wrench_mode_transition_experiments_v1.gd")

func strict_decreasing(values: Array) -> bool:
	for i in range(1, values.size()):
		if not float(values[i]) < float(values[i - 1]):
			return false
	return true

func _init() -> void:
	var checks := 0

	# Four mandatory persistent-contact transition families localize as continuous roots.
	var all := E.all_transition_probe()
	assert(bool(all["ok"])); checks += 1
	var expected_kind := {"tangent":"STICK_TO_SLIDE","rolling":"STICK_TO_ROLL","torsion":"STICK_TO_SPIN","support":"SUPPORT_TO_SEPARATION"}
	var expected_mode := {"tangent":"slide","rolling":"roll","torsion":"spin"}
	var expected_hypothesis := {"tangent":"STICK_TO_SLIDE_CANDIDATE","rolling":"STICK_TO_ROLL_CANDIDATE","torsion":"STICK_TO_SPIN_CANDIDATE"}
	for channel in ["tangent", "rolling", "torsion", "support"]:
		var event: Dictionary = all["events"][channel]
		var exact_root := float(all["roots"][channel])
		assert(bool(event["ok"])); checks += 1
		assert(String(event["kind"]) == String(expected_kind[channel])); checks += 1
		assert(String(event["channel"]) == channel); checks += 1
		assert(absf(float(event["time"]) - exact_root) < 1.0e-10); checks += 1
		assert(float(event["uncertainty"]) <= 1.0e-10); checks += 1
		assert(float(event["guard_before"]) > 0.0); checks += 1
		assert(float(event["guard_after"]) <= 0.0); checks += 1
		assert(String(event["pre_state"]["manifold_identity"]) == String(event["post_state"]["manifold_identity"])); checks += 1
		if channel == "support":
			assert(bool(event["pre_state"]["active"])); checks += 1
			assert(not bool(event["post_state"]["active"])); checks += 1
			assert(event["post_state"]["mode_transition_hypothesis"]["contact"] == "SEPARATION_CANDIDATE"); checks += 1
			assert(event["post_state"]["accepted_generalized_impulse"] == [0.0,0.0,0.0,0.0,0.0]); checks += 1
		else:
			assert(String(event["pre_state"]["modes"][channel]) == "stick"); checks += 1
			assert(String(event["post_state"]["modes"][channel]) == String(expected_mode[channel])); checks += 1
			assert(String(event["transition_hypothesis"][channel]) == String(expected_hypothesis[channel])); checks += 1

	# Accepted friction/moment stays saturated after the root; the continuous guard, not accepted impulse, carries the sign change.
	var tangent_event: Dictionary = all["events"]["tangent"]
	assert(absf(float(tangent_event["post_state"]["accepted_generalized_impulse"][0]) - float(tangent_event["post_state"]["limits"]["tangent"])) < 1.0e-15); checks += 1
	assert(float(tangent_event["post_state"]["generalized_velocity_after"][0]) > 0.0); checks += 1
	assert(float(tangent_event["guard_after"]) < 0.0); checks += 1

	# Root refinement is strict for all four transition families.
	var final_errors: Dictionary = {}
	for channel in ["tangent", "rolling", "torsion", "support"]:
		var refined := E.refinement_probe(channel)
		assert(bool(refined["ok"])); checks += 1
		assert(refined["errors"].size() == 4 and refined["uncertainties"].size() == 4); checks += 1
		assert(strict_decreasing(refined["errors"])); checks += 1
		assert(strict_decreasing(refined["uncertainties"])); checks += 1
		for i in range(4):
			assert(float(refined["errors"][i]) <= float(refined["uncertainties"][i]) + 1.0e-15); checks += 1
		final_errors[channel] = refined["errors"][3]
		assert(float(refined["errors"][3]) < 1.0e-9); checks += 1

	# Temporal resolution distinguishes exact simultaneous semantics from merely near-coincident mode roots.
	var coarse := E.near_coincident_probe(1.0e-3)
	var fine := E.near_coincident_probe(1.0e-5)
	assert(bool(coarse["ok"]) and bool(fine["ok"])); checks += 1
	assert(coarse["event_ids"] == ["rolling:STICK_TO_ROLL", "tangent:STICK_TO_SLIDE"]); checks += 1
	assert(coarse["deferred_events"].is_empty()); checks += 1
	assert(fine["event_ids"] == ["tangent:STICK_TO_SLIDE"]); checks += 1
	assert(fine["deferred_events"].size() == 1); checks += 1
	assert(String(fine["deferred_events"][0]["event_id"]) == "rolling:STICK_TO_ROLL"); checks += 1
	assert(absf(float(fine["time"]) - 1.0) < 1.0e-9); checks += 1
	assert(absf(float(fine["deferred_events"][0]["time"]) - 1.0002) < 1.0e-9); checks += 1
	assert(float(fine["deferred_events"][0]["time"]) - float(fine["time"]) > 1.99e-4); checks += 1

	# Caller identity ordering and event-spec ordering are exact deterministic inputs, not hidden physics.
	var replay := E.near_coincident_probe(1.0e-5)
	var reversed := E.near_coincident_probe(1.0e-5, true, true)
	assert(bool(replay["ok"]) and bool(reversed["ok"])); checks += 1
	assert(String(replay["signature"]) == String(fine["signature"])); checks += 1
	assert(String(reversed["signature"]) == String(fine["signature"])); checks += 1
	assert(float(reversed["time"]) == float(fine["time"])); checks += 1
	assert(String(reversed["members"][0]["pre_state"]["manifold_identity"]) == String(fine["members"][0]["pre_state"]["manifold_identity"])); checks += 1
	assert(String(reversed["members"][0]["transition_hypothesis"]["tangent"]) == "STICK_TO_SLIDE_CANDIDATE"); checks += 1

	# Fail closed: invalid contracts never silently become a transition.
	var tangent_eval := E.evaluator(E.single_channel_config("tangent", 1.0))
	var mismatch := L.localize_transition(tangent_eval, "tangent", "STICK_TO_ROLL", 0.0, 2.0)
	assert(not bool(mismatch["ok"]) and mismatch["code"] == "TRANSITION_KIND_CHANNEL_MISMATCH"); checks += 1
	var bad_channel := L.localize_transition(tangent_eval, "bogus", "BOGUS", 0.0, 2.0)
	assert(not bool(bad_channel["ok"]) and bad_channel["code"] == "BAD_TRANSITION_CHANNEL"); checks += 1
	var past := L.localize_transition(tangent_eval, "tangent", "STICK_TO_SLIDE", 1.1, 0.5)
	assert(not bool(past["ok"]) and past["code"] == "TRANSITION_ALREADY_REACHED"); checks += 1
	var absent := L.localize_transition(tangent_eval, "tangent", "STICK_TO_SLIDE", 0.0, 0.5)
	assert(not bool(absent["ok"]) and absent["code"] == "NO_TRANSITION_IN_HORIZON"); checks += 1
	var empty_set := L.next_event_set(tangent_eval, [], 0.0, 2.0)
	assert(not bool(empty_set["ok"]) and empty_set["code"] == "EMPTY_EVENT_SPEC_SET"); checks += 1
	var bad_resolution := L.next_event_set(tangent_eval, [{"channel":"tangent"}], 0.0, 2.0, 1.0e-9, -1.0)
	assert(not bool(bad_resolution["ok"]) and bad_resolution["code"] == "BAD_SIMULTANEOUS_RESOLUTION"); checks += 1
	var incomplete_eval := func(_time: float) -> Dictionary: return {"ok":true,"observation":{},"solved":{}}
	var incomplete := L.localize_transition(incomplete_eval, "tangent", "STICK_TO_SLIDE", 0.0, 2.0)
	assert(not bool(incomplete["ok"]) and incomplete["code"] == "EVALUATOR_INCOMPLETE"); checks += 1
	var invalid_state_eval := func(time: float) -> Dictionary:
		return {"ok":true,"observation":{"body_a":"A","body_b":"B","members":["p0"]},"solved":{"normal_support":1.0,"generalized_impulse":[0.2,0.0,0.0,0.0,0.0],"generalized_velocity_after":[0.2,0.0,0.0,0.0,0.0],"limits":{"tangent":0.5,"rolling":1.0,"torsion":1.0}},"guards":{"tangent":1.0-time}}
	var invalid_state := L.localize_transition(invalid_state_eval, "tangent", "STICK_TO_SLIDE", 0.0, 2.0)
	assert(not bool(invalid_state["ok"]) and invalid_state["code"] == "EVALUATOR_STATE_INVALID"); checks += 1

	print("FABRIC0.18-B Mode Transition Localization Acceptance: PASS (%d assertions) roots=(%.12f,%.12f,%.12f,%.12f) refine_final=%s coarse=%s fine=%s" % [
		checks,
		float(all["events"]["tangent"]["time"]), float(all["events"]["rolling"]["time"]), float(all["events"]["torsion"]["time"]), float(all["events"]["support"]["time"]),
		str(final_errors), str(coarse["event_ids"]), str(fine["event_ids"])
	])
	quit(0)
