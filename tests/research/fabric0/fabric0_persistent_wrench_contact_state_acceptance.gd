extends SceneTree

const S = preload("res://scripts/research/fabric0/fabric0_persistent_wrench_contact_state_v1.gd")

func obs(a := "A", b := "B", members := ["p0", "p1", "p2", "p3"]) -> Dictionary:
	return {"body_a": a, "body_b": b, "members": members}

func solved(normal := 2.0, impulse := [0.1, 0.0, 0.02, 0.0, 0.01], velocity := [0.0, 0.0, 0.0, 0.0, 0.0], limits := {"tangent": 0.5, "rolling": 0.1, "torsion": 0.05}) -> Dictionary:
	return {"normal_support": normal, "generalized_impulse": impulse, "generalized_velocity_after": velocity, "limits": limits}

func _init() -> void:
	var checks := 0

	# Direct bridge from canonical 0.17 persistent manifold + generalized wrench result.
	var fabric_manifold := {
		"ok": true, "pair_id": "A|B", "feature_key": "A|ra:A:1|ib:B:2",
		"points": [
			{"id": "A|ra:A:1|ib:B:2|p3"}, {"id": "A|ra:A:1|ib:B:2|p1"},
			{"id": "A|ra:A:1|ib:B:2|p0"}, {"id": "A|ra:A:1|ib:B:2|p2"},
		]
	}
	var bridged_observation := S.observation_from_fabric_manifold(fabric_manifold)
	assert(bool(bridged_observation["ok"])); checks += 1
	assert(bridged_observation["body_a"] == "A" and bridged_observation["body_b"] == "B"); checks += 1
	assert(bridged_observation["members"].size() == 4); checks += 1
	var c_result := {"ok": true, "normal_impulse": 2.0, "generalized_impulse": [0.1,0.0,0.02,0.0,0.01], "generalized_velocity_after": [0.0,0.0,0.0,0.0,0.0], "limits": {"tangent":0.5,"rolling":0.1,"torsion":0.05}}
	var bridged_solved := S.solved_from_generalized_wrench(c_result)
	assert(bool(bridged_solved["ok"])); checks += 1
	var bridged_state := S.begin(bridged_observation, bridged_solved, 0.5)
	assert(bool(bridged_state["ok"])); checks += 1
	assert(String(bridged_state["manifold_identity"]).contains("|p0") and String(bridged_state["manifold_identity"]).contains("|p3")); checks += 1
	var missing_point_id := S.observation_from_fabric_manifold({"ok":true,"pair_id":"A|B","points":[{}]})
	assert(not bool(missing_point_id["ok"]) and missing_point_id["code"] == "FABRIC_MANIFOLD_POINT_ID_MISSING"); checks += 1

	# Canonical pair + manifold identity is independent of caller/member order.
	var a := S.begin(obs("B", "A", ["p3", "p1", "p0", "p2"]), solved(), 1.0)
	var b := S.begin(obs("A", "B", ["p0", "p1", "p2", "p3"]), solved(), 1.0)
	assert(bool(a["ok"]) and bool(b["ok"])); checks += 1
	assert(a["pair_id"] == "A|B" and b["pair_id"] == "A|B"); checks += 1
	assert(a["manifold_identity"] == b["manifold_identity"]); checks += 1
	assert(a["member_ids"] == ["p0", "p1", "p2", "p3"]); checks += 1
	assert(String(a["signature"]) == String(b["signature"])); checks += 1

	# Initial state carries no inherited impulse as physical truth.
	assert(a["identity_epoch"] == 0 and a["update_count"] == 0); checks += 1
	assert(a["contact_age"] == 0.0); checks += 1
	assert(a["warm_start_proposal"] == [0.0, 0.0, 0.0, 0.0, 0.0]); checks += 1
	assert(a["warm_start_source"] == "NONE_INITIAL_STATE"); checks += 1
	assert(a["accepted_generalized_impulse"] == [0.1, 0.0, 0.02, 0.0, 0.01]); checks += 1
	assert(bool(a["solver_refresh_required"])); checks += 1
	assert(a["modes"] == {"tangent": "stick", "rolling": "stick", "torsion": "stick"}); checks += 1

	# Continuity: previous accepted impulse becomes only a projected proposal.
	var next_solved := solved(2.0, [0.03, 0.04, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0, 0.0], {"tangent": 0.05, "rolling": 0.01, "torsion": 0.005})
	var c := S.advance(a, obs(), next_solved, 1.25)
	assert(bool(c["ok"])); checks += 1
	assert(bool(c["identity_continued"])); checks += 1
	assert(c["identity_epoch"] == 0 and c["update_count"] == 1); checks += 1
	assert(absf(float(c["contact_age"]) - 0.25) < 1.0e-15); checks += 1
	assert(c["first_seen_time"] == 1.0 and c["last_seen_time"] == 1.25); checks += 1
	assert(c["warm_start_source"] == "PREVIOUS_ACCEPTED_PROJECTED_PROPOSAL"); checks += 1
	assert(Vector2(float(c["warm_start_proposal"][0]), float(c["warm_start_proposal"][1])).length() <= 0.05 + 1.0e-15); checks += 1
	assert(Vector2(float(c["warm_start_proposal"][2]), float(c["warm_start_proposal"][3])).length() <= 0.01 + 1.0e-15); checks += 1
	assert(absf(float(c["warm_start_proposal"][4])) <= 0.005 + 1.0e-15); checks += 1
	assert(c["accepted_generalized_impulse"] == [0.03, 0.04, 0.0, 0.0, 0.0]); checks += 1
	assert(c["accepted_generalized_impulse"] != c["warm_start_proposal"]); checks += 1

	# Reordered members preserve identity; changed members reset continuity and warm-start.
	var reorder := S.advance(c, obs("B", "A", ["p2", "p0", "p3", "p1"]), solved(), 1.5)
	assert(bool(reorder["ok"]) and bool(reorder["identity_continued"])); checks += 1
	assert(reorder["identity_epoch"] == 0 and reorder["update_count"] == 2); checks += 1
	var changed := S.advance(reorder, obs("A", "B", ["p0", "p1", "p2", "p4"]), solved(), 1.75)
	assert(bool(changed["ok"]) and not bool(changed["identity_continued"])); checks += 1
	assert(changed["identity_epoch"] == 1 and changed["update_count"] == 0); checks += 1
	assert(changed["first_seen_time"] == 1.75 and changed["contact_age"] == 0.0); checks += 1
	assert(changed["warm_start_proposal"] == [0.0, 0.0, 0.0, 0.0, 0.0]); checks += 1

	# Mode classification: moving channels require active-set saturation.
	var slide := S.begin(obs(), solved(2.0, [0.5, 0.0, 0.0, 0.0, 0.0], [0.2, 0.0, 0.0, 0.0, 0.0]), 2.0)
	assert(bool(slide["ok"]) and slide["modes"]["tangent"] == "slide"); checks += 1
	var roll := S.begin(obs(), solved(2.0, [0.0, 0.0, 0.1, 0.0, 0.0], [0.0, 0.0, 0.3, 0.0, 0.0]), 2.0)
	assert(bool(roll["ok"]) and roll["modes"]["rolling"] == "roll"); checks += 1
	var spin := S.begin(obs(), solved(2.0, [0.0, 0.0, 0.0, 0.0, -0.05], [0.0, 0.0, 0.0, 0.0, -0.4]), 2.0)
	assert(bool(spin["ok"]) and spin["modes"]["torsion"] == "spin"); checks += 1

	# Mode changes are hypotheses only; 0.18-B will localize their event times.
	var slide_from_stick := S.advance(a, obs(), solved(2.0, [0.5, 0.0, 0.02, 0.0, 0.01], [0.2, 0.0, 0.0, 0.0, 0.0]), 1.1)
	assert(bool(slide_from_stick["ok"])); checks += 1
	assert(slide_from_stick["mode_transition_hypothesis"]["tangent"] == "STICK_TO_SLIDE_CANDIDATE"); checks += 1

	# Fail closed when a moving DOF is not on its admissible wrench boundary.
	var unresolved := S.begin(obs(), solved(2.0, [0.2, 0.0, 0.0, 0.0, 0.0], [0.2, 0.0, 0.0, 0.0, 0.0]), 2.0)
	assert(not bool(unresolved["ok"]) and unresolved["code"] == "MODE_CONSTRAINT_UNRESOLVED"); checks += 1
	assert(unresolved["channel"] == "tangent"); checks += 1

	# Separation clears physical and warm-start impulse state.
	var separated := S.separate(c, 1.3)
	assert(bool(separated["ok"]) and not bool(separated["active"])); checks += 1
	assert(separated["normal_support"] == 0.0); checks += 1
	assert(separated["accepted_generalized_impulse"] == [0.0, 0.0, 0.0, 0.0, 0.0]); checks += 1
	assert(separated["warm_start_proposal"] == [0.0, 0.0, 0.0, 0.0, 0.0]); checks += 1
	assert(separated["modes"] == {"tangent": "open", "rolling": "open", "torsion": "open"}); checks += 1
	assert(separated["mode_transition_hypothesis"]["contact"] == "SEPARATION_CANDIDATE"); checks += 1

	# Zero normal support is explicitly inactive even if represented at the boundary.
	var zero_support := S.begin(obs(), solved(0.0, [0.0, 0.0, 0.0, 0.0, 0.0]), 3.0)
	assert(bool(zero_support["ok"]) and not bool(zero_support["active"])); checks += 1

	# Long-horizon identity bookkeeping has no hidden state drift.
	var steady := S.begin(obs(), solved(3.0, [0.0, 0.0, 0.0, 0.0, 0.0]), 0.0)
	for i in range(1, 10001):
		steady = S.advance(steady, obs("B", "A", ["p3", "p2", "p1", "p0"]), solved(3.0, [0.0, 0.0, 0.0, 0.0, 0.0]), float(i) * 0.001)
		assert(bool(steady["ok"]))
	assert(steady["update_count"] == 10000); checks += 1
	assert(absf(float(steady["contact_age"]) - 10.0) < 1.0e-12); checks += 1
	assert(steady["identity_epoch"] == 0); checks += 1
	assert(steady["accepted_generalized_impulse"] == [0.0, 0.0, 0.0, 0.0, 0.0]); checks += 1
	assert(steady["warm_start_proposal"] == [0.0, 0.0, 0.0, 0.0, 0.0]); checks += 1

	# Fail-closed validation.
	var bad_time := S.advance(c, obs(), solved(), 1.0)
	assert(not bool(bad_time["ok"]) and bad_time["code"] == "TIME_REVERSAL"); checks += 1
	var bad_support := S.begin(obs(), solved(-1.0), 0.0)
	assert(not bool(bad_support["ok"]) and bad_support["code"] == "BAD_NORMAL_SUPPORT"); checks += 1
	var bad_members := S.begin(obs("A", "B", ["p0", "p0"]), solved(), 0.0)
	assert(not bool(bad_members["ok"]) and bad_members["code"] == "DUPLICATE_MANIFOLD_MEMBER_ID"); checks += 1
	var bad_dimension := S.begin(obs(), solved(2.0, [0.0, 0.0], [0.0, 0.0]), 0.0)
	assert(not bool(bad_dimension["ok"]) and bad_dimension["code"] == "BAD_GENERALIZED_DIMENSION"); checks += 1
	var outside := S.begin(obs(), solved(2.0, [0.6, 0.0, 0.0, 0.0, 0.0]), 0.0)
	assert(not bool(outside["ok"]) and outside["code"] == "IMPULSE_OUTSIDE_LIMIT"); checks += 1

	print("FABRIC0.18-A Persistent Wrench Contact State Acceptance: PASS (%d assertions) steady_updates=%d age=%.12f identity=%s" % [checks, steady["update_count"], steady["contact_age"], steady["manifold_identity"]])
	quit(0)
