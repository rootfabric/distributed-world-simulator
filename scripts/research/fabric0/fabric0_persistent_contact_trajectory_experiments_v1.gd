class_name Fabric0PersistentContactTrajectoryExperimentsV1
extends RefCounted

const Trajectory = preload("res://scripts/research/fabric0/fabric0_persistent_contact_trajectory_v1.gd")

static func refinement_probe() -> Dictionary:
	var tolerances := [1.0e-8, 1.0e-9, 1.0e-10]
	var reference := Trajectory.run(1.0e-11)
	if not bool(reference.get("ok", false)):
		return {"ok": false, "code": "REFERENCE_TRAJECTORY_FAILED", "detail": reference}
	var errors: Array = []
	var state_errors: Array = []
	var runs: Array = []
	for tolerance_any in tolerances:
		var run := Trajectory.run(float(tolerance_any))
		if not bool(run.get("ok", false)):
			return {"ok": false, "code": "REFINEMENT_TRAJECTORY_FAILED", "tolerance": tolerance_any, "detail": run}
		runs.append(run)
		errors.append(_max_time_error(run, reference))
		state_errors.append(_max_state_error(run, reference))
	return {"ok": true, "tolerances": tolerances, "reference": reference, "runs": runs, "time_errors": errors, "state_errors": state_errors}

static func determinism_probe() -> Dictionary:
	var canonical := Trajectory.run(1.0e-9, false, false)
	var reverse_contacts := Trajectory.run(1.0e-9, true, false)
	var reverse_specs := Trajectory.run(1.0e-9, false, true)
	if not bool(canonical.get("ok", false)) or not bool(reverse_contacts.get("ok", false)) or not bool(reverse_specs.get("ok", false)):
		return {"ok": false, "code": "DETERMINISM_RUN_FAILED", "canonical": canonical, "reverse_contacts": reverse_contacts, "reverse_specs": reverse_specs}
	return {
		"ok": true,
		"canonical": canonical,
		"reverse_contacts": reverse_contacts,
		"reverse_specs": reverse_specs,
		"contact_signature_equal": String(canonical["signature"]) == String(reverse_contacts["signature"]),
		"spec_signature_equal": String(canonical["signature"]) == String(reverse_specs["signature"]),
		"contact_state_error": _max_state_error(canonical, reverse_contacts),
		"spec_state_error": _max_state_error(canonical, reverse_specs),
	}

static func _max_time_error(a: Dictionary, b: Dictionary) -> float:
	var at: Array = a["timeline_times"]
	var bt: Array = b["timeline_times"]
	if at.size() != bt.size(): return INF
	var out := 0.0
	for i in range(at.size()): out = maxf(out, absf(float(at[i]) - float(bt[i])))
	return out

static func _max_state_error(a: Dictionary, b: Dictionary) -> float:
	var av: Array = a["event_state_vector"]
	var bv: Array = b["event_state_vector"]
	if av.size() != bv.size(): return INF
	var out := 0.0
	for i in range(av.size()): out = maxf(out, absf(float(av[i]) - float(bv[i])))
	var ab: Dictionary = a["final_body"]
	var bb: Dictionary = b["final_body"]
	out = maxf(out, (Vector3(ab["v"]) - Vector3(bb["v"])).length())
	out = maxf(out, (Vector3(ab["w"]) - Vector3(bb["w"])).length())
	return out
