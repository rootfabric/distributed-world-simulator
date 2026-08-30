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
