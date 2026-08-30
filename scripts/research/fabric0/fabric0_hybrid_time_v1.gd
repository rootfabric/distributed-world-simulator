class_name Fabric0HybridTimeV1
extends RefCounted

const Physical = preload("res://scripts/research/fabric0/fabric0_nonsmooth_fabric_v1.gd")

const TIME_EPSILON := 1.0e-10
const GUARD_EPSILON := 1.0e-10
const EVENT_TIME_TOLERANCE := 1.0e-11
const EVENT_LOCALIZATION_ITERATIONS := 64
const MAX_EVENTS_PER_ADVANCE := 32

# =============================================================================
# DIMENSION HELPERS
# =============================================================================

static func dim_dimensionless() -> Dictionary:
	return Physical.dim_dimensionless()

static func dim_time() -> Dictionary:
	return Physical.dim_time()

static func dim_length() -> Dictionary:
	return Physical.dim(1)

static func dim_velocity() -> Dictionary:
	return Physical.dim_velocity()

static func dim_acceleration() -> Dictionary:
	return Physical.dim(1, 0, -2)

static func dim_voltage() -> Dictionary:
	return Physical.dim_voltage()

static func dim_current() -> Dictionary:
	return Physical.dim_current()

static func dim_force() -> Dictionary:
	return Physical.dim_force()

static func dim_mul(a: Dictionary, b: Dictionary) -> Dictionary:
	return Physical.dim_mul(a, b)

static func dim_div(a: Dictionary, b: Dictionary) -> Dictionary:
	return Physical.dim_div(a, b)

static func dim_equal(a: Dictionary, b: Dictionary) -> bool:
	return Physical.dim_equal(a, b)

static func dim_string(a: Dictionary) -> String:
	return Physical.dim_string(a)

# =============================================================================
# EXPRESSION DSL FOR CONTINUOUS TIME / EVENTS
# =============================================================================

static func expr_constant(value: float, dimension: Dictionary = {}) -> Dictionary:
	return {"op": "constant", "value": value, "dimension": dimension.duplicate(true)}

static func expr_state(name: String) -> Dictionary:
	return {"op": "state", "name": name}

static func expr_parameter(name: String) -> Dictionary:
	return {"op": "parameter", "name": name}

static func expr_time() -> Dictionary:
	return {"op": "time"}

static func expr_add(a: Dictionary, b: Dictionary) -> Dictionary:
	return {"op": "add", "a": a, "b": b}

static func expr_sub(a: Dictionary, b: Dictionary) -> Dictionary:
	return {"op": "sub", "a": a, "b": b}

static func expr_mul(a: Dictionary, b: Dictionary) -> Dictionary:
	return {"op": "mul", "a": a, "b": b}

static func expr_div(a: Dictionary, b: Dictionary) -> Dictionary:
	return {"op": "div", "a": a, "b": b}

static func expr_neg(a: Dictionary) -> Dictionary:
	return {"op": "neg", "a": a}

static func expr_pow_int(a: Dictionary, exponent: int) -> Dictionary:
	return {"op": "pow_int", "a": a, "exponent": exponent}

# =============================================================================
# TIMELINE MODEL
# =============================================================================

static func new_timeline(physical_network: Dictionary = {}) -> Dictionary:
	return {
		"time": 0.0,
		"states": {},
		"parameters": {},
		"modes": {},
		"mode": "",
		"transitions": [],
		"events": [],
		"diagnostics": [],
		"step_revision": 0,
		"topology_revision": 0,
		"physical_network": physical_network,
	}

static func add_state(
	timeline: Dictionary,
	name: String,
	initial_value: float,
	dimension: Dictionary,
	nominal: float = 1.0
) -> bool:
	if name.is_empty() or timeline["states"].has(name) or nominal <= 0.0:
		return false
	timeline["states"][name] = {
		"value": initial_value,
		"dimension": dimension.duplicate(true),
		"nominal": nominal,
	}
	return true

static func add_parameter(
	timeline: Dictionary,
	name: String,
	value: float,
	dimension: Dictionary
) -> bool:
	if name.is_empty() or timeline["parameters"].has(name):
		return false
	timeline["parameters"][name] = {
		"value": value,
		"dimension": dimension.duplicate(true),
	}
	return true

static func set_parameter_value(timeline: Dictionary, name: String, value: float) -> bool:
	if not timeline["parameters"].has(name):
		return false
	timeline["parameters"][name]["value"] = value
	return true

# flows: state_name -> derivative expression.
# Missing states have derivative 0.
static func add_mode(timeline: Dictionary, mode_id: String, flows: Dictionary) -> bool:
	if mode_id.is_empty() or timeline["modes"].has(mode_id):
		return false
	for state_name in flows.keys():
		if not timeline["states"].has(state_name):
			return false
		var inferred := _infer_expr_dimension(timeline, flows[state_name])
		if not bool(inferred.get("ok", false)):
			timeline["diagnostics"].append({"code": "FLOW_DIMENSION_ERROR", "mode": mode_id, "state": String(state_name), "reason": inferred})
			return false
		var expected := dim_div(timeline["states"][state_name]["dimension"], dim_time())
		if not dim_equal(inferred["dimension"], expected):
			timeline["diagnostics"].append({
				"code": "FLOW_DIMENSION_MISMATCH",
				"mode": mode_id,
				"state": String(state_name),
				"expected": dim_string(expected),
				"actual": dim_string(inferred["dimension"]),
			})
			return false
	timeline["modes"][mode_id] = {"flows": flows.duplicate(true)}
	return true

static func set_initial_mode(timeline: Dictionary, mode_id: String) -> bool:
	if not timeline["modes"].has(mode_id):
		return false
	timeline["mode"] = mode_id
	return true

# Transition schema:
# {
#   id,
#   from_modes:[...],
#   to_mode,
#   guard:{expr, nominal, direction}, # direction -1 / 0 / +1
#   resets:{state_name: expr},
#   topology_ops:[{op:"set_bond_active", bond_id, active}],
#   priority
# }
static func add_transition(timeline: Dictionary, transition: Dictionary) -> bool:
	var transition_id := String(transition.get("id", ""))
	if transition_id.is_empty():
		return false
	for existing in timeline["transitions"]:
		if String(existing["id"]) == transition_id:
			return false
	var from_modes: Array = transition.get("from_modes", [])
	var to_mode := String(transition.get("to_mode", ""))
	if from_modes.is_empty() or not timeline["modes"].has(to_mode):
		return false
	for mode_id in from_modes:
		if not timeline["modes"].has(String(mode_id)):
			return false
	var guard: Dictionary = transition.get("guard", {})
	if not guard.has("expr") or float(guard.get("nominal", 0.0)) <= 0.0:
		return false
	var direction := int(guard.get("direction", 0))
	if direction < -1 or direction > 1:
		return false
	var guard_dim := _infer_expr_dimension(timeline, guard["expr"])
	if not bool(guard_dim.get("ok", false)):
		timeline["diagnostics"].append({"code": "GUARD_DIMENSION_ERROR", "transition": transition_id, "reason": guard_dim})
		return false
	var resets: Dictionary = transition.get("resets", {})
	for state_name in resets.keys():
		if not timeline["states"].has(state_name):
			return false
		var inferred := _infer_expr_dimension(timeline, resets[state_name])
		if not bool(inferred.get("ok", false)):
			timeline["diagnostics"].append({"code": "RESET_DIMENSION_ERROR", "transition": transition_id, "state": String(state_name), "reason": inferred})
			return false
		if not dim_equal(inferred["dimension"], timeline["states"][state_name]["dimension"]):
			timeline["diagnostics"].append({
				"code": "RESET_DIMENSION_MISMATCH",
				"transition": transition_id,
				"state": String(state_name),
				"expected": dim_string(timeline["states"][state_name]["dimension"]),
				"actual": dim_string(inferred["dimension"]),
			})
			return false
	for op in transition.get("topology_ops", []):
		if String(op.get("op", "")) != "set_bond_active":
			return false
	var normalized := {
		"id": transition_id,
		"from_modes": from_modes.duplicate(true),
		"to_mode": to_mode,
		"guard": {
			"expr": guard["expr"].duplicate(true),
			"nominal": float(guard["nominal"]),
			"direction": direction,
			"dimension": guard_dim["dimension"],
		},
		"resets": resets.duplicate(true),
		"topology_ops": transition.get("topology_ops", []).duplicate(true),
		"priority": int(transition.get("priority", 0)),
	}
	timeline["transitions"].append(normalized)
	return true

static func read_state(timeline: Dictionary, name: String) -> float:
	return float(timeline["states"][name]["value"])

static func read_mode(timeline: Dictionary) -> String:
	return String(timeline["mode"])

# =============================================================================
# ADVANCE: MACROSTEP TRANSACTION
# =============================================================================

static func advance(timeline: Dictionary, delta: float) -> Dictionary:
	if delta < 0.0 or String(timeline["mode"]).is_empty():
		return {"ok": false, "code": "BAD_ADVANCE_REQUEST"}
	if delta <= TIME_EPSILON:
		return {"ok": true, "events": 0, "time": float(timeline["time"])}
	var snapshot := _capture_advance_snapshot(timeline)
	timeline["diagnostics"] = []
	var remaining := delta
	var events_in_advance := 0
	while remaining > TIME_EPSILON:
		var segment_start_time := float(timeline["time"])
		var segment_start_state := _state_values(timeline)
		var end_state := _integrate_mode(timeline, segment_start_state, segment_start_time, remaining)
		var candidate := _find_earliest_event(timeline, segment_start_state, end_state, segment_start_time, remaining)
		if not bool(candidate.get("found", false)):
			_commit_state_values(timeline, end_state)
			timeline["time"] = segment_start_time + remaining
			remaining = 0.0
			break

		var event_dt := float(candidate["dt"])
		var transition: Dictionary = candidate["transition"]
		var event_state := _integrate_mode(timeline, segment_start_state, segment_start_time, event_dt)
		var event_time := segment_start_time + event_dt
		_commit_state_values(timeline, event_state)
		timeline["time"] = event_time

		var jump_result := _apply_transition_transaction(timeline, transition, event_state, event_time)
		if not bool(jump_result.get("ok", false)):
			var diagnostic := jump_result.duplicate(true)
			_restore_advance_snapshot(timeline, snapshot)
			timeline["diagnostics"] = [diagnostic]
			return {"ok": false, "code": String(diagnostic.get("code", "EVENT_TRANSACTION_FAILED")), "rolled_back": true}

		events_in_advance += 1
		if events_in_advance > MAX_EVENTS_PER_ADVANCE:
			var diagnostic := {
				"code": "ZENO_OR_EVENT_STORM",
				"limit": MAX_EVENTS_PER_ADVANCE,
				"requested_delta": delta,
			}
			_restore_advance_snapshot(timeline, snapshot)
			timeline["diagnostics"] = [diagnostic]
			return {"ok": false, "code": "ZENO_OR_EVENT_STORM", "rolled_back": true}

		remaining -= event_dt
		if remaining < TIME_EPSILON:
			remaining = 0.0

	timeline["step_revision"] = int(timeline["step_revision"]) + 1
	return {
		"ok": true,
		"events": events_in_advance,
		"time": float(timeline["time"]),
		"step_revision": int(timeline["step_revision"]),
	}

# =============================================================================
# EVENT LOCALIZATION / JUMP
# =============================================================================

static func _eligible_transitions(timeline: Dictionary) -> Array:
	var result: Array = []
	var mode := String(timeline["mode"])
	for transition in timeline["transitions"]:
		if mode in transition["from_modes"]:
			result.append(transition)
	return result

static func _find_earliest_event(
	timeline: Dictionary,
	start_state: Dictionary,
	end_state: Dictionary,
	start_time: float,
	delta: float
) -> Dictionary:
	var candidates: Array = []
	for transition in _eligible_transitions(timeline):
		var guard: Dictionary = transition["guard"]
		var g0 := _eval_expr(timeline, guard["expr"], start_state, start_time)
		var g1 := _eval_expr(timeline, guard["expr"], end_state, start_time + delta)
		if not bool(g0.get("ok", false)) or not bool(g1.get("ok", false)):
			continue
		if not _crossed(float(g0["value"]), float(g1["value"]), int(guard["direction"]), float(guard["nominal"])):
			continue
		var event_dt := _localize_event(timeline, transition, start_state, start_time, delta)
		candidates.append({"transition": transition, "dt": event_dt})
	if candidates.is_empty():
		return {"found": false}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if absf(float(a["dt"]) - float(b["dt"])) > EVENT_TIME_TOLERANCE:
			return float(a["dt"]) < float(b["dt"])
		var pa := int(a["transition"]["priority"])
		var pb := int(b["transition"]["priority"])
		if pa != pb:
			return pa < pb
		return String(a["transition"]["id"]) < String(b["transition"]["id"])
	)
	return {"found": true, "transition": candidates[0]["transition"], "dt": float(candidates[0]["dt"])}

static func _crossed(g0: float, g1: float, direction: int, nominal: float) -> bool:
	var eps := GUARD_EPSILON * maxf(nominal, 1.0)
	match direction:
		1:
			return g0 < -eps and g1 >= 0.0
		-1:
			return g0 > eps and g1 <= 0.0
		_:
			return (g0 < -eps and g1 >= 0.0) or (g0 > eps and g1 <= 0.0)

static func _localize_event(
	timeline: Dictionary,
	transition: Dictionary,
	start_state: Dictionary,
	start_time: float,
	delta: float
) -> float:
	var guard: Dictionary = transition["guard"]
	var low := 0.0
	var high := delta
	var g_low := float(_eval_expr(timeline, guard["expr"], start_state, start_time)["value"])
	for _i in range(EVENT_LOCALIZATION_ITERATIONS):
		if high - low <= EVENT_TIME_TOLERANCE:
			break
		var mid := 0.5 * (low + high)
		var mid_state := _integrate_mode(timeline, start_state, start_time, mid)
		var g_mid := float(_eval_expr(timeline, guard["expr"], mid_state, start_time + mid)["value"])
		var direction := int(guard["direction"])
		if direction > 0:
			if g_mid >= 0.0: high = mid
			else:
				low = mid
				g_low = g_mid
		elif direction < 0:
			if g_mid <= 0.0: high = mid
			else:
				low = mid
				g_low = g_mid
		else:
			if (g_low <= 0.0 and g_mid >= 0.0) or (g_low >= 0.0 and g_mid <= 0.0):
				high = mid
			else:
				low = mid
				g_low = g_mid
	return high

static func _apply_transition_transaction(
	timeline: Dictionary,
	transition: Dictionary,
	pre_state: Dictionary,
	event_time: float
) -> Dictionary:
	# 1) Evaluate all resets against the same immutable pre-event snapshot.
	var reset_values := {}
	for state_name in transition["resets"].keys():
		var evaluated := _eval_expr(timeline, transition["resets"][state_name], pre_state, event_time)
		if not bool(evaluated.get("ok", false)):
			return {"ok": false, "code": "RESET_EVALUATION_FAILED", "transition": String(transition["id"]), "state": String(state_name)}
		reset_values[state_name] = float(evaluated["value"])

	# 2) Validate all topology operations before changing anything.
	var topology_validation := _validate_topology_transaction(timeline, transition["topology_ops"])
	if not bool(topology_validation.get("ok", false)):
		var failure := topology_validation.duplicate(true)
		failure["transition"] = String(transition["id"])
		return failure

	var pre_hash := state_hash(timeline)
	var pre_mode := String(timeline["mode"])
	var pre_states := pre_state.duplicate(true)
	var topology_before := int(timeline["topology_revision"])

	# 3) Commit resets simultaneously.
	for state_name in reset_values.keys():
		timeline["states"][state_name]["value"] = float(reset_values[state_name])

	# 4) Commit mode and topology transaction.
	timeline["mode"] = String(transition["to_mode"])
	var topology_changed := _commit_topology_transaction(timeline, transition["topology_ops"])
	if topology_changed:
		timeline["topology_revision"] = topology_before + 1

	var post_states := _state_values(timeline)
	var sequence: int = timeline["events"].size() + 1
	var event := {
		"event_id": "fabric0/event/%06d/%s" % [sequence, String(transition["id"])],
		"sequence": sequence,
		"transition_id": String(transition["id"]),
		"time": event_time,
		"pre_mode": pre_mode,
		"post_mode": String(timeline["mode"]),
		"pre_states": pre_states,
		"post_states": post_states,
		"pre_state_hash": pre_hash,
		"topology_revision_before": topology_before,
		"topology_revision_after": int(timeline["topology_revision"]),
	}
	event["post_state_hash"] = state_hash(timeline)
	timeline["events"].append(event)
	return {"ok": true, "event": event}

static func _validate_topology_transaction(timeline: Dictionary, ops: Array) -> Dictionary:
	if ops.is_empty():
		return {"ok": true}
	var network: Dictionary = timeline["physical_network"]
	if network.is_empty() or not network.has("bonds"):
		return {"ok": false, "code": "TOPOLOGY_TRANSACTION_NO_NETWORK"}
	var seen := {}
	for op in ops:
		if String(op.get("op", "")) != "set_bond_active":
			return {"ok": false, "code": "TOPOLOGY_TRANSACTION_UNSUPPORTED_OP"}
		var bond_id := String(op.get("bond_id", ""))
		if bond_id.is_empty() or seen.has(bond_id):
			return {"ok": false, "code": "TOPOLOGY_TRANSACTION_DUPLICATE_OR_EMPTY_BOND", "bond_id": bond_id}
		seen[bond_id] = true
		if _find_bond_index(network, bond_id) < 0:
			return {"ok": false, "code": "TOPOLOGY_TRANSACTION_UNKNOWN_BOND", "bond_id": bond_id}
	return {"ok": true}

static func _commit_topology_transaction(timeline: Dictionary, ops: Array) -> bool:
	var changed := false
	var network: Dictionary = timeline["physical_network"]
	for op in ops:
		var bond_id := String(op["bond_id"])
		var index := _find_bond_index(network, bond_id)
		var target := bool(op["active"])
		if bool(network["bonds"][index]["active"]) != target:
			network["bonds"][index]["active"] = target
