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

