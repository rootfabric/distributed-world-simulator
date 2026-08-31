class_name Fabric0PersistentContactTrajectoryV1
extends RefCounted

const Graph = preload("res://scripts/research/fabric0/fabric0_persistent_wrench_graph_v1.gd")
const GraphExperiments = preload("res://scripts/research/fabric0/fabric0_persistent_wrench_graph_experiments_v1.gd")
const Locator = preload("res://scripts/research/fabric0/fabric0_persistent_wrench_mode_event_locator_v1.gd")
const State = preload("res://scripts/research/fabric0/fabric0_persistent_wrench_contact_state_v1.gd")

const IMPACT_HEIGHT := 0.1
const IMPACT_VY := -1.0
const IMPACT_HORIZON := 0.2
const MODE_START := 0.2
const MODE_HORIZON := 1.1
const FINAL_TIME := 1.2
const MODE_VELOCITY_TOLERANCE := 1.0e-10

static func run(root_tolerance: float = 1.0e-9, reverse_contacts: bool = false, reverse_event_specs: bool = false) -> Dictionary:
	if not is_finite(root_tolerance) or root_tolerance <= 0.0:
		return {"ok": false, "code": "BAD_TRAJECTORY_ROOT_TOLERANCE"}
	if root_tolerance > 1.0e-4:
		return {"ok": false, "code": "TRAJECTORY_ROOT_TOLERANCE_TOO_COARSE", "tolerance": root_tolerance}

	var impact := _localize_impact(root_tolerance)
	if not bool(impact.get("ok", false)):
		return impact
	var contacts := GraphExperiments._contacts(0.08)
	if reverse_contacts:
		contacts.reverse()
	var impact_body := {
		"id": "PLANK",
		"mass": 10.0,
		"inertia": Vector3(4.0, 2.5, 6.0),
		"v": Vector3(0.0, IMPACT_VY, 0.0),
		"w": Vector3.ZERO,
	}
	var impact_solve := Graph.solve(impact_body, contacts, {}, {
		"time": float(impact["time"]), "tolerance": 1.0e-12, "iterations": 120000, "step_scale": 0.8,
	})
	if not bool(impact_solve.get("ok", false)):
		return {"ok": false, "code": "IMPACT_ACQUISITION_SOLVE_FAILED", "detail": impact_solve}
	var states := _states_from_graph(impact_solve)
	var impact_post_v: Vector3 = impact_solve["post_body"]["v"]
	var impact_post_w: Vector3 = impact_solve["post_body"]["w"]
	if impact_post_v.length() > 1.0e-10 or impact_post_w.length() > 1.0e-10:
		return {"ok": false, "code": "IMPACT_DID_NOT_ACQUIRE_PERSISTENT_SUPPORT", "v": impact_post_v, "w": impact_post_w}

	var evaluator := func(time: float) -> Dictionary:
		return _locator_sample(time, reverse_contacts)
	var specs: Array = [
		{"channel": "tangent", "kind": "STICK_TO_SLIDE"},
		{"channel": "rolling", "kind": "STICK_TO_ROLL"},
		{"channel": "torsion", "kind": "STICK_TO_SPIN"},
		{"channel": "support", "kind": "SUPPORT_TO_SEPARATION"},
	]
	if reverse_event_specs:
		specs.reverse()
	var localized: Array = []
	for spec_any in specs:
		var spec: Dictionary = spec_any
		var event := Locator.localize_transition(
			evaluator, String(spec["channel"]), String(spec["kind"]), MODE_START, MODE_HORIZON,
			root_tolerance, 96, {"velocity_tolerance": MODE_VELOCITY_TOLERANCE}
		)
		if not bool(event.get("ok", false)):
			return {"ok": false, "code": "LIVE_MODE_EVENT_LOCALIZATION_FAILED", "spec": spec, "detail": event}
		localized.append(event)
	localized.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if absf(float(a["time"]) - float(b["time"])) > 1.0e-14:
			return float(a["time"]) < float(b["time"])
		return String(a["event_id"]) < String(b["event_id"])
	)

	var records: Array = []
	var max_energy_ledger_error := float(impact_solve["energy_ledger_error"])
	var contact_dissipation := minf(0.0, float(impact_solve["kinetic_delta"]))
	var max_normal_complementarity := float(impact_solve["normal_complementarity_error"])
	var max_matrix_symmetry := float(impact_solve["matrix_symmetry_error"])
	var event_state_vector: Array = []
	var previous_time := float(impact["time"])
	for event_any in localized:
		var event: Dictionary = event_any
		if float(event["time"]) <= previous_time:
			return {"ok": false, "code": "NONCAUSAL_EVENT_ORDER", "previous_time": previous_time, "event": event}
		var resolve_probe := maxf(1.0e-3, 64.0 * root_tolerance)
		var resolve_time := float(event["time"]) + resolve_probe
		var graph := _live_graph_with_history(resolve_time, states, reverse_contacts)
		if not bool(graph.get("ok", false)):
			return {"ok": false, "code": "EVENT_RESOLVE_GRAPH_FAILED", "event": event, "detail": graph}
		states = _states_from_graph(graph)
		var left: Dictionary = graph["per_contact"]["L"]
		var right: Dictionary = graph["per_contact"]["R"]
		var left_state: Dictionary = left["persistent_state"]
		var right_state: Dictionary = right["persistent_state"]
		var expected := _expected_post(event)
		var semantic := _check_post_semantics(event, left_state)
		if not bool(semantic.get("ok", false)):
			return semantic
		max_energy_ledger_error = maxf(max_energy_ledger_error, float(graph["energy_ledger_error"]))
		contact_dissipation += minf(0.0, float(graph["kinetic_delta"]))
		max_normal_complementarity = maxf(max_normal_complementarity, float(graph["normal_complementarity_error"]))
		max_matrix_symmetry = maxf(max_matrix_symmetry, float(graph["matrix_symmetry_error"]))
		var body: Dictionary = graph["post_body"]
		var v: Vector3 = body["v"]
		var w: Vector3 = body["w"]
		event_state_vector.append_array([v.x, v.y, v.z, w.x, w.y, w.z, float(left["normal_impulse"]), float(right["normal_impulse"])])
		records.append({
			"event_id": event["event_id"], "time": event["time"], "uncertainty": event["uncertainty"],
			"resolve_time": resolve_time, "expected_post": expected,
			"left_modes": Dictionary(left_state["modes"]).duplicate(true), "right_modes": Dictionary(right_state["modes"]).duplicate(true),
			"left_active": left_state["active"], "right_active": right_state["active"],
			"left_support": left["normal_impulse"], "right_support": right["normal_impulse"],
			"reaction_force_impulse": graph["reaction_force_impulse"], "reaction_moment_impulse": graph["reaction_moment_impulse"],
			"kinetic_delta": graph["kinetic_delta"], "energy_ledger_error": graph["energy_ledger_error"],
		})
		previous_time = float(event["time"])

	var final_graph := _live_graph_with_history(FINAL_TIME, states, reverse_contacts)
	if not bool(final_graph.get("ok", false)):
		return {"ok": false, "code": "FINAL_GRAPH_FAILED", "detail": final_graph}
	var final_left: Dictionary = final_graph["per_contact"]["L"]
	var final_right: Dictionary = final_graph["per_contact"]["R"]
	var final_left_state: Dictionary = final_left["persistent_state"]
	var final_right_state: Dictionary = final_right["persistent_state"]
	if bool(final_left_state["active"]):
		return {"ok": false, "code": "FINAL_LEFT_SUPPORT_NOT_SEPARATED", "state": final_left_state}
	if not bool(final_right_state["active"]):
		return {"ok": false, "code": "FINAL_RIGHT_SUPPORT_LOST", "state": final_right_state}
	if String(final_right_state["modes"]["tangent"]) != "slide" or String(final_right_state["modes"]["rolling"]) != "roll" or String(final_right_state["modes"]["torsion"]) != "spin":
		return {"ok": false, "code": "FINAL_RIGHT_MODES_WRONG", "modes": final_right_state["modes"]}

	max_energy_ledger_error = maxf(max_energy_ledger_error, float(final_graph["energy_ledger_error"]))
	contact_dissipation += minf(0.0, float(final_graph["kinetic_delta"]))
	max_normal_complementarity = maxf(max_normal_complementarity, float(final_graph["normal_complementarity_error"]))
	max_matrix_symmetry = maxf(max_matrix_symmetry, float(final_graph["matrix_symmetry_error"]))
	var final_body: Dictionary = final_graph["post_body"]
	var fv: Vector3 = final_body["v"]
	var fw: Vector3 = final_body["w"]
	var timeline_ids: Array = ["impact:ACQUIRE_PERSISTENT_SUPPORT"]
	var timeline_times: Array = [float(impact["time"])]
	for record_any in records:
		var record: Dictionary = record_any
		timeline_ids.append(String(record["event_id"]))
		timeline_times.append(float(record["time"]))
	var signature := JSON.stringify({
		"timeline_ids": timeline_ids,
		"timeline_times": timeline_times,
		"final_v": [fv.x, fv.y, fv.z], "final_w": [fw.x, fw.y, fw.z],
		"final_left_active": final_left_state["active"], "final_right_modes": final_right_state["modes"],
	}, "", false)
	return {
		"ok": true,
		"kind": "UNIFIED_PERSISTENT_CONTACT_TRAJECTORY",
		"impact": impact,
		"impact_solve": impact_solve,
		"events": records,
		"timeline_ids": timeline_ids,
		"timeline_times": timeline_times,
		"event_state_vector": event_state_vector,
		"final_graph": final_graph,
		"final_body": final_body,
		"final_left_state": final_left_state,
		"final_right_state": final_right_state,
		"max_energy_ledger_error": max_energy_ledger_error,
		"contact_dissipation": contact_dissipation,
		"max_normal_complementarity_error": max_normal_complementarity,
		"max_matrix_symmetry_error": max_matrix_symmetry,
		"signature": signature,
	}

static func _localize_impact(tolerance: float) -> Dictionary:
	var lo := 0.0
	var hi := IMPACT_HORIZON
	var g_lo := IMPACT_HEIGHT + IMPACT_VY * lo
	var g_hi := IMPACT_HEIGHT + IMPACT_VY * hi
	if g_lo <= 0.0 or g_hi > 0.0:
		return {"ok": false, "code": "IMPACT_NOT_BRACKETED", "g_lo": g_lo, "g_hi": g_hi}
	var iterations := 0
	while hi - lo > tolerance:
		iterations += 1
		if iterations > 256:
			return {"ok": false, "code": "IMPACT_ROOT_ITERATION_LIMIT"}
		var mid := 0.5 * (lo + hi)
		var g := IMPACT_HEIGHT + IMPACT_VY * mid
		if g > 0.0:
			lo = mid
		else:
			hi = mid
	return {"ok": true, "kind": "IMPACT_ACQUIRE_PERSISTENT_SUPPORT", "time": hi, "bracket": [lo, hi], "uncertainty": hi - lo, "iterations": iterations}

static func _live_graph_with_history(time: float, previous_states: Dictionary, reverse_contacts: bool = false) -> Dictionary:
	var graph := _live_graph(time, {}, reverse_contacts)
	if not bool(graph.get("ok", false)):
		return graph
	var by_id: Dictionary = {}
	for contact_any in Array(graph["contacts"]):
		var contact: Dictionary = contact_any
		by_id[String(contact["contact_id"])] = contact
	for id in ["L", "R"]:
		var contact: Dictionary = by_id[id]
		var per: Dictionary = graph["per_contact"][id]
		var obs := {"body_a": String(contact.get("anchor_id", "WORLD")), "body_b": "PLANK", "members": Array(contact["member_ids"]).duplicate()}
		var gv: Array = per["generalized_velocity_after"]
		var solved := {
			"normal_support": per["normal_impulse"],
			"generalized_impulse": [per["tangent_impulse"].x, per["tangent_impulse"].y, per["rolling_impulse"].x, per["rolling_impulse"].y, per["torsion_impulse"]],
			"generalized_velocity_after": [gv[1], gv[2], gv[3], gv[4], gv[5]],
			"limits": Dictionary(per["limits"]).duplicate(true),
		}
		var previous = previous_states.get(id, {})
		var persistent: Dictionary
		if float(per["normal_impulse"]) <= 1.0e-12:
			var seed: Dictionary
			if previous is Dictionary and bool(Dictionary(previous).get("ok", false)):
				seed = Dictionary(previous)
			else:
				seed = State.begin(obs, {"normal_support": 0.0, "generalized_impulse": [0.0,0.0,0.0,0.0,0.0], "generalized_velocity_after": [0.0,0.0,0.0,0.0,0.0], "limits": {"tangent":0.0,"rolling":0.0,"torsion":0.0}}, time, {"velocity_tolerance": MODE_VELOCITY_TOLERANCE})
			persistent = State.separate(seed, time)
			persistent["limits"] = {"tangent":0.0,"rolling":0.0,"torsion":0.0}
		elif previous is Dictionary and bool(Dictionary(previous).get("ok", false)):
			persistent = State.advance(Dictionary(previous), obs, solved, time, {"velocity_tolerance": MODE_VELOCITY_TOLERANCE})
		else:
			persistent = State.begin(obs, solved, time, {"velocity_tolerance": MODE_VELOCITY_TOLERANCE})
		if not bool(persistent.get("ok", false)):
			return {"ok": false, "code": "TRAJECTORY_PERSISTENT_STATE_REJECTED", "contact_id": id, "detail": persistent}
		per["persistent_state"] = persistent
		graph["per_contact"][id] = per
	return graph

static func _live_graph(time: float, previous_states: Dictionary = {}, reverse_contacts: bool = false) -> Dictionary:
	var s := maxf(0.0, time - 0.1)
	var normal_impulse := 1.0
	var tangent_impulse := maxf(0.0, s - 0.10) * 1.6
	var roll_impulse := maxf(0.0, s - 0.30) * 0.30
	var torsion_impulse := maxf(0.0, s - 0.50) * 0.22
	var load_x := 0.20 + maxf(0.0, s - 0.60) * 1.8
	var mass := 10.0
	var inertia := Vector3(4.0, 2.5, 6.0)
	var body := {
		"id": "PLANK", "mass": mass, "inertia": inertia,
		"v": Vector3(tangent_impulse / mass, -normal_impulse / mass, 0.0),
		"w": Vector3(roll_impulse / inertia.x, torsion_impulse / inertia.y, -load_x * normal_impulse / inertia.z),
	}
	var contacts := GraphExperiments._contacts(0.08)
	if reverse_contacts:
		contacts.reverse()
	return Graph.solve(body, contacts, previous_states, {
		"time": time, "tolerance": 1.0e-11, "iterations": 160000, "step_scale": 0.8,
	})

static func _locator_sample(time: float, reverse_contacts: bool = false) -> Dictionary:
	var graph := _live_graph(time, {}, reverse_contacts)
	if not bool(graph.get("ok", false)):
		return graph
	var left: Dictionary = graph["per_contact"]["L"]
	var state: Dictionary = left["persistent_state"]
	var gv: Array = left["generalized_velocity_after"]
	var limits: Dictionary = left["limits"]
	var tangent_speed := Vector2(float(gv[1]), float(gv[2])).length()
	var rolling_speed := Vector2(float(gv[3]), float(gv[4])).length()
	var torsion_speed := absf(float(gv[5]))
	var guards := {
		"tangent": float(limits["tangent"]) - Vector2(left["tangent_impulse"]).length() + MODE_VELOCITY_TOLERANCE - tangent_speed,
		"rolling": float(limits["rolling"]) - Vector2(left["rolling_impulse"]).length() + MODE_VELOCITY_TOLERANCE - rolling_speed,
		"torsion": float(limits["torsion"]) - absf(float(left["torsion_impulse"])) + MODE_VELOCITY_TOLERANCE - torsion_speed,
		"support": float(left["normal_impulse"]) - maxf(0.0, float(gv[0])),
	}
	return {
		"ok": true,
		"observation": {"body_a": "FLOOR", "body_b": "PLANK", "members": ["L|p0", "L|p1", "L|p2", "L|p3"]},
		"solved": {
			"normal_support": left["normal_impulse"],
			"generalized_impulse": [left["tangent_impulse"].x, left["tangent_impulse"].y, left["rolling_impulse"].x, left["rolling_impulse"].y, left["torsion_impulse"]],
			"generalized_velocity_after": [gv[1], gv[2], gv[3], gv[4], gv[5]],
			"limits": limits,
		},
		"guards": guards,
		"graph": graph,
		"left_state": state,
	}

static func _states_from_graph(graph: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for id in ["L", "R"]:
		out[id] = Dictionary(Dictionary(graph["per_contact"])[id])["persistent_state"]
	return out

static func _expected_post(event: Dictionary) -> String:
	match String(event["channel"]):
		"tangent": return "slide"
		"rolling": return "roll"
		"torsion": return "spin"
		"support": return "open"
	return ""

static func _check_post_semantics(event: Dictionary, left_state: Dictionary) -> Dictionary:
	var channel := String(event["channel"])
	if channel == "support":
		if bool(left_state.get("active", true)):
			return {"ok": false, "code": "TRAJECTORY_SUPPORT_EVENT_DID_NOT_OPEN", "event": event, "state": left_state}
		if Dictionary(left_state["modes"]) != {"tangent": "open", "rolling": "open", "torsion": "open"}:
			return {"ok": false, "code": "TRAJECTORY_SUPPORT_OPEN_MODES_WRONG", "state": left_state}
		return {"ok": true}
	var expected := _expected_post(event)
	if String(Dictionary(left_state["modes"])[channel]) != expected:
		return {"ok": false, "code": "TRAJECTORY_POST_MODE_MISMATCH", "channel": channel, "expected": expected, "actual": Dictionary(left_state["modes"])[channel]}
	return {"ok": true}
