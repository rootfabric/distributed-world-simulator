class_name Fabric0CoupledHybridDAEV1
extends RefCounted

const Physical = preload("res://scripts/research/fabric0/fabric0_nonsmooth_fabric_v1.gd")

const EPSILON := 1.0e-10
const PIVOT_EPSILON := 1.0e-12
const NEWTON_TOLERANCE := 1.0e-11
const NEWTON_MAX_ITERATIONS := 32
const NEWTON_MAX_LINE_SEARCH := 12
const EVENT_TIME_TOLERANCE := 1.0e-11
const EVENT_LOCALIZATION_ITERATIONS := 64
const MAX_EVENTS_PER_ADVANCE := 32
const MAX_EVENT_ITERATIONS := 16
const GUARD_TOLERANCE := 1.0e-10

# =============================================================================
# DIMENSIONS
# =============================================================================

static func dim_dimensionless() -> Dictionary: return Physical.dim_dimensionless()
static func dim_time() -> Dictionary: return Physical.dim_time()
static func dim_length() -> Dictionary: return Physical.dim(1)
static func dim_velocity() -> Dictionary: return Physical.dim_velocity()
static func dim_acceleration() -> Dictionary: return Physical.dim(1, 0, -2)
static func dim_mass() -> Dictionary: return Physical.dim(0, 1)
static func dim_force() -> Dictionary: return Physical.dim_force()
static func dim_impulse() -> Dictionary: return Physical.dim_mul(Physical.dim_force(), Physical.dim_time())
static func dim_energy() -> Dictionary: return Physical.dim_energy()
static func dim_mul(a: Dictionary, b: Dictionary) -> Dictionary: return Physical.dim_mul(a, b)
static func dim_div(a: Dictionary, b: Dictionary) -> Dictionary: return Physical.dim_div(a, b)
static func dim_pow(a: Dictionary, n: int) -> Dictionary: return Physical.dim_pow(a, n)
static func dim_equal(a: Dictionary, b: Dictionary) -> bool: return Physical.dim_equal(a, b)
static func dim_string(a: Dictionary) -> String: return Physical.dim_string(a)

# =============================================================================
# EXPRESSION DSL
# =============================================================================

static func expr_constant(value: float, dimension: Dictionary = {}) -> Dictionary:
	return {"op":"constant", "value":value, "dimension":dimension.duplicate(true)}

static func expr_state(name: String) -> Dictionary: return {"op":"state", "name":name}
static func expr_algebraic(name: String) -> Dictionary: return {"op":"algebraic", "name":name}
static func expr_parameter(name: String) -> Dictionary: return {"op":"parameter", "name":name}
static func expr_time() -> Dictionary: return {"op":"time"}
static func expr_bond_active(bond_id: String) -> Dictionary: return {"op":"bond_active", "bond_id":bond_id}
static func expr_pre_state(name: String) -> Dictionary: return {"op":"pre_state", "name":name}
static func expr_post_state(name: String) -> Dictionary: return {"op":"post_state", "name":name}
static func expr_jump(name: String) -> Dictionary: return {"op":"jump", "name":name}
static func expr_add(a: Dictionary, b: Dictionary) -> Dictionary: return {"op":"add", "a":a, "b":b}
static func expr_sub(a: Dictionary, b: Dictionary) -> Dictionary: return {"op":"sub", "a":a, "b":b}
static func expr_mul(a: Dictionary, b: Dictionary) -> Dictionary: return {"op":"mul", "a":a, "b":b}
static func expr_div(a: Dictionary, b: Dictionary) -> Dictionary: return {"op":"div", "a":a, "b":b}
static func expr_neg(a: Dictionary) -> Dictionary: return {"op":"neg", "a":a}
static func expr_pow_int(a: Dictionary, n: int) -> Dictionary: return {"op":"pow_int", "a":a, "exponent":n}

static func residual(expr: Dictionary, nominal: float) -> Dictionary:
	assert(nominal > 0.0)
	return {"expr":expr.duplicate(true), "nominal":nominal}

static func inequality(expr: Dictionary, nominal: float, label: String = "") -> Dictionary:
	assert(nominal > 0.0)
	return {"expr":expr.duplicate(true), "nominal":nominal, "label":label}

static func jump_branch(branch_id: String, residuals: Array, inequalities: Array = [], priority: int = 0) -> Dictionary:
	return {
		"id":branch_id,
		"residuals":residuals.duplicate(true),
		"inequalities":inequalities.duplicate(true),
		"priority":priority,
	}

# =============================================================================
# SYSTEM MODEL
# =============================================================================

static func new_system(physical_network: Dictionary = {}) -> Dictionary:
	return {
		"time":0.0,
		"states":{},
		"algebraics":{},
		"parameters":{},
		"modes":{},
		"mode":"",
		"transitions":[],
		"events":[],
		"diagnostics":[],
		"physical_network":physical_network,
		"topology_revision":0,
		"step_revision":0,
		"solver_stats":{},
	}

static func add_state(system: Dictionary, name: String, value: float, dimension: Dictionary, nominal: float = 1.0) -> bool:
	if name.is_empty() or system["states"].has(name) or nominal <= 0.0: return false
	system["states"][name] = {"value":value, "dimension":dimension.duplicate(true), "nominal":nominal}
	return true

static func add_algebraic(system: Dictionary, name: String, value: float, dimension: Dictionary, nominal: float = 1.0) -> bool:
	if name.is_empty() or system["algebraics"].has(name) or nominal <= 0.0: return false
	system["algebraics"][name] = {"value":value, "dimension":dimension.duplicate(true), "nominal":nominal}
	return true

static func add_parameter(system: Dictionary, name: String, value: float, dimension: Dictionary) -> bool:
	if name.is_empty() or system["parameters"].has(name): return false
	system["parameters"][name] = {"value":value, "dimension":dimension.duplicate(true)}
	return true

static func set_parameter_value(system: Dictionary, name: String, value: float) -> bool:
	if not system["parameters"].has(name): return false
	system["parameters"][name]["value"] = value
	return true

# mode = flows(state -> expr), algebraic residuals F(x,y,p,t)=0.
static func add_mode(system: Dictionary, mode_id: String, flows: Dictionary, algebraic_residuals: Array) -> bool:
	if mode_id.is_empty() or system["modes"].has(mode_id): return false
	if algebraic_residuals.size() != system["algebraics"].size():
		system["diagnostics"].append({"code":"DAE_NON_SQUARE_ALGEBRAIC_SYSTEM", "mode":mode_id})
		return false
	for state_name in flows.keys():
		if not system["states"].has(state_name): return false
		var inferred := _infer_expr_dimension(system, flows[state_name], {})
		if not bool(inferred.get("ok", false)):
			system["diagnostics"].append({"code":"DAE_FLOW_DIMENSION_ERROR", "mode":mode_id, "state":String(state_name), "reason":inferred})
			return false
		var expected := dim_div(system["states"][state_name]["dimension"], dim_time())
		if not dim_equal(inferred["dimension"], expected):
			system["diagnostics"].append({"code":"DAE_FLOW_DIMENSION_MISMATCH", "mode":mode_id, "state":String(state_name), "expected":dim_string(expected), "actual":dim_string(inferred["dimension"])})
			return false
	var normalized: Array = []
	for row in algebraic_residuals:
		if not row.has("expr") or float(row.get("nominal",0.0)) <= 0.0: return false
		var inferred := _infer_expr_dimension(system, row["expr"], {})
		if not bool(inferred.get("ok", false)):
			system["diagnostics"].append({"code":"DAE_RESIDUAL_DIMENSION_ERROR", "mode":mode_id, "reason":inferred})
			return false
		normalized.append({"expr":row["expr"].duplicate(true), "nominal":float(row["nominal"]), "dimension":inferred["dimension"]})
	system["modes"][mode_id] = {"flows":flows.duplicate(true), "residuals":normalized}
	return true

static func set_initial_mode(system: Dictionary, mode_id: String) -> bool:
	if not system["modes"].has(mode_id): return false
	system["mode"] = mode_id
	return true

# transition:
# id, from_modes, to_mode,
# guard {expr, nominal, direction, kind:"crossing"|"condition"},
# jump {post_states:[...], unknowns:{name:{dimension,nominal,initial}}, branches:[...]}, optional
# topology_ops, priority.
static func add_transition(system: Dictionary, transition: Dictionary) -> bool:
	var transition_id := String(transition.get("id", ""))
	if transition_id.is_empty(): return false
	for existing in system["transitions"]:
		if String(existing["id"]) == transition_id: return false
	var from_modes: Array = transition.get("from_modes", [])
	var to_mode := String(transition.get("to_mode", ""))
	if from_modes.is_empty() or not system["modes"].has(to_mode): return false
	for mode_id in from_modes:
