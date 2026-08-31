extends SceneTree

const T = preload("res://scripts/research/fabric0/fabric0_persistent_contact_trajectory_v1.gd")
const E = preload("res://scripts/research/fabric0/fabric0_persistent_contact_trajectory_experiments_v1.gd")

func strict_decreasing(values: Array) -> bool:
	for i in range(1, values.size()):
		if not float(values[i]) < float(values[i - 1]): return false
	return true

func _init() -> void:
	var checks := 0
	var r := T.run(1.0e-9)
	assert(bool(r["ok"])); checks += 1
	assert(r["kind"] == "UNIFIED_PERSISTENT_CONTACT_TRAJECTORY"); checks += 1

	var expected_ids := [
		"impact:ACQUIRE_PERSISTENT_SUPPORT",
		"tangent:STICK_TO_SLIDE",
		"rolling:STICK_TO_ROLL",
		"torsion:STICK_TO_SPIN",
		"support:SUPPORT_TO_SEPARATION",
	]
	assert(r["timeline_ids"] == expected_ids); checks += 1
	assert(r["timeline_times"].size() == 5); checks += 1
	for i in range(1, 5):
		assert(float(r["timeline_times"][i]) > float(r["timeline_times"][i - 1])); checks += 1

	# Free-flight impact boundary and persistent acquisition.
	assert(absf(float(r["impact"]["time"]) - 0.1) < 1.0e-9); checks += 1
	assert(float(r["impact"]["uncertainty"]) <= 1.0e-9); checks += 1
	assert(int(r["impact"]["iterations"]) > 0); checks += 1
	var impact: Dictionary = r["impact_solve"]
	assert(bool(impact["ok"])); checks += 1
	assert(Vector3(impact["post_body"]["v"]).length() < 2.0e-11); checks += 1
	assert(Vector3(impact["post_body"]["w"]).length() < 2.0e-11); checks += 1
	assert(absf(float(impact["per_contact"]["L"]["normal_impulse"]) - 5.0) < 2.0e-10); checks += 1
	assert(absf(float(impact["per_contact"]["R"]["normal_impulse"]) - 5.0) < 2.0e-10); checks += 1
	assert(impact["per_contact"]["L"]["persistent_state"]["modes"] == {"tangent":"stick","rolling":"stick","torsion":"stick"}); checks += 1
	assert(impact["per_contact"]["R"]["persistent_state"]["modes"] == {"tangent":"stick","rolling":"stick","torsion":"stick"}); checks += 1
	assert(absf(float(impact["kinetic_before"]) - 5.0) < 1.0e-12); checks += 1
	assert(float(impact["kinetic_after"]) < 1.0e-20); checks += 1
	assert(absf(float(impact["kinetic_delta"]) + 5.0) < 1.0e-12); checks += 1
	assert(float(impact["energy_ledger_error"]) < 1.0e-14); checks += 1

	# Live C/B roots from one common evaluator.
	var expected_times := [0.4812500006, 0.4997095626, 0.6909090985, 1.1444444444]
	var expected_modes := [
		{"tangent":"slide","rolling":"stick","torsion":"stick"},
		{"tangent":"slide","rolling":"roll","torsion":"stick"},
		{"tangent":"slide","rolling":"roll","torsion":"spin"},
		{"tangent":"open","rolling":"open","torsion":"open"},
	]
	assert(r["events"].size() == 4); checks += 1
	for i in range(4):
		var event: Dictionary = r["events"][i]
		assert(absf(float(event["time"]) - expected_times[i]) < 2.0e-8); checks += 1
		assert(float(event["uncertainty"]) <= 1.0e-9); checks += 1
		assert(event["left_modes"] == expected_modes[i]); checks += 1
		assert(float(event["energy_ledger_error"]) < 1.0e-14); checks += 1
		assert(float(event["kinetic_delta"]) <= 1.0e-12); checks += 1
		assert(float(event["resolve_time"]) > float(event["time"])); checks += 1

	assert(bool(r["events"][0]["left_active"])); checks += 1
	assert(bool(r["events"][1]["left_active"])); checks += 1
	assert(bool(r["events"][2]["left_active"])); checks += 1
	assert(not bool(r["events"][3]["left_active"])); checks += 1
	for i in range(4):
		assert(bool(r["events"][i]["right_active"])); checks += 1

	# The live signed KKT guards bracket the same localized boundaries.
	var channel_by_index := ["tangent", "rolling", "torsion", "support"]
	for i in range(4):
		var t := float(r["events"][i]["time"])
		var before := T._locator_sample(t - 1.0e-6)
		var after := T._locator_sample(t + 1.0e-6)
		var channel: String = String(channel_by_index[i])
		assert(bool(before["ok"]) and bool(after["ok"])); checks += 1
		assert(float(before["guards"][channel]) > 0.0); checks += 1
		assert(float(after["guards"][channel]) < 0.0); checks += 1

	# Persistent identity is carried from impact, but accepted physics is always freshly canonicalized.
	var left_final: Dictionary = r["final_left_state"]
	var right_final: Dictionary = r["final_right_state"]
	assert(absf(float(left_final["first_seen_time"]) - 0.1) < 1.0e-12); checks += 1
	assert(absf(float(right_final["first_seen_time"]) - 0.1) < 1.0e-12); checks += 1
	assert(absf(float(left_final["contact_age"]) - 1.1) < 1.0e-12); checks += 1
	assert(absf(float(right_final["contact_age"]) - 1.1) < 1.0e-12); checks += 1
	assert(int(left_final["identity_epoch"]) == 0 and int(right_final["identity_epoch"]) == 0); checks += 1
	assert(not bool(left_final["active"])); checks += 1
	assert(bool(right_final["active"])); checks += 1
	assert(left_final["modes"] == {"tangent":"open","rolling":"open","torsion":"open"}); checks += 1
	assert(right_final["modes"] == {"tangent":"slide","rolling":"roll","torsion":"spin"}); checks += 1
	assert(left_final["accepted_generalized_impulse"] == [0.0,0.0,0.0,0.0,0.0]); checks += 1
	assert(left_final["limits"] == {"tangent":0.0,"rolling":0.0,"torsion":0.0}); checks += 1
	assert(float(right_final["normal_support"]) > 1.05); checks += 1

	# Whole trajectory ledgers stay passive/closed.
	assert(float(r["contact_dissipation"]) < -5.5); checks += 1
	assert(float(r["max_energy_ledger_error"]) < 1.0e-14); checks += 1
	assert(float(r["max_normal_complementarity_error"]) < 2.0e-10); checks += 1
	assert(float(r["max_matrix_symmetry_error"]) < 1.0e-14); checks += 1
	assert(float(r["final_graph"]["min_open_normal_velocity"]) > 0.01); checks += 1
	assert(float(r["final_graph"]["kinetic_delta"]) < 0.0); checks += 1
	assert(float(r["final_graph"]["energy_ledger_error"]) < 1.0e-14); checks += 1

	# Refinement: event time and event-resolved state converge strictly.
	var refinement := E.refinement_probe()
	assert(bool(refinement["ok"])); checks += 1
	assert(refinement["tolerances"] == [1.0e-8,1.0e-9,1.0e-10]); checks += 1
	assert(strict_decreasing(refinement["time_errors"])); checks += 1
	assert(strict_decreasing(refinement["state_errors"])); checks += 1
	assert(float(refinement["time_errors"][0]) < 5.0e-9); checks += 1
	assert(float(refinement["time_errors"][2]) < 8.0e-11); checks += 1
	assert(float(refinement["state_errors"][0]) < 2.0e-9); checks += 1
	assert(float(refinement["state_errors"][2]) < 8.0e-11); checks += 1
	for run_any in refinement["runs"]:
		var run: Dictionary = run_any
		assert(run["timeline_ids"] == expected_ids); checks += 1
		assert(float(run["max_energy_ledger_error"]) < 1.0e-14); checks += 1
		assert(float(run["max_normal_complementarity_error"]) < 2.0e-10); checks += 1

	# Determinism: contact presentation and event-spec presentation are not physics.
	var det := E.determinism_probe()
	assert(bool(det["ok"])); checks += 1
	assert(bool(det["contact_signature_equal"])); checks += 1
	assert(bool(det["spec_signature_equal"])); checks += 1
	assert(float(det["contact_state_error"]) == 0.0); checks += 1
	assert(float(det["spec_state_error"]) == 0.0); checks += 1
	assert(det["canonical"]["timeline_times"] == det["reverse_contacts"]["timeline_times"]); checks += 1
	assert(det["canonical"]["timeline_times"] == det["reverse_specs"]["timeline_times"]); checks += 1

	# Fail closed rather than silently advancing under unusable event resolution.
	var bad_zero := T.run(0.0)
	assert(not bool(bad_zero["ok"]) and bad_zero["code"] == "BAD_TRAJECTORY_ROOT_TOLERANCE"); checks += 1
	var bad_negative := T.run(-1.0e-9)
	assert(not bool(bad_negative["ok"]) and bad_negative["code"] == "BAD_TRAJECTORY_ROOT_TOLERANCE"); checks += 1
	var coarse := T.run(1.0e-3)
	assert(not bool(coarse["ok"]) and coarse["code"] == "TRAJECTORY_ROOT_TOLERANCE_TOO_COARSE"); checks += 1

	print("FABRIC0.18-D Unified Persistent Contact Trajectory Acceptance: PASS (%d assertions) timeline=%s times=%s diss=%.12f comp=%s refine_time=%s refine_state=%s" % [checks, str(r["timeline_ids"]), str(r["timeline_times"]), float(r["contact_dissipation"]), String.num_scientific(float(r["max_normal_complementarity_error"])), str(refinement["time_errors"]), str(refinement["state_errors"])])
	quit(0)
