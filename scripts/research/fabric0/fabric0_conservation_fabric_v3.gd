class_name Fabric0ConservationFabricV3
extends RefCounted

const EPSILON := 1.0e-10
const PIVOT_EPSILON := 1.0e-12
const NEWTON_TOLERANCE := 1.0e-10
const NEWTON_STEP_TOLERANCE := 1.0e-11
const NEWTON_MAX_ITERATIONS := 48
const NEWTON_MAX_LINE_SEARCH := 16
const DIMENSION_KEYS := ["L", "M", "T", "I", "Theta", "N", "J"]

# -----------------------------------------------------------------------------
# Dimension algebra: seven SI base dimensions. Angles use SI's unit-one
# dimensional status; their explicit radian symbol stays in unit metadata.
# -----------------------------------------------------------------------------

static func dim(
	length: int = 0,
	mass: int = 0,
	time: int = 0,
	current: int = 0,
	temperature: int = 0,
	amount: int = 0,
	luminous_intensity: int = 0
) -> Dictionary:
	return {
		"L": length,
		"M": mass,
		"T": time,
		"I": current,
		"Theta": temperature,
		"N": amount,
		"J": luminous_intensity,
	}

static func dim_dimensionless() -> Dictionary:
	return dim()

static func dim_length() -> Dictionary:
	return dim(1)

static func dim_mass() -> Dictionary:
	return dim(0, 1)

static func dim_time() -> Dictionary:
	return dim(0, 0, 1)

static func dim_current() -> Dictionary:
	return dim(0, 0, 0, 1)

static func dim_temperature() -> Dictionary:
	return dim(0, 0, 0, 0, 1)

static func dim_amount() -> Dictionary:
	return dim(0, 0, 0, 0, 0, 1)

static func dim_luminous_intensity() -> Dictionary:
	return dim(0, 0, 0, 0, 0, 0, 1)

static func dim_power() -> Dictionary:
	return dim(2, 1, -3)

static func dim_energy() -> Dictionary:
	return dim(2, 1, -2)

static func dim_voltage() -> Dictionary:
	return dim(2, 1, -3, -1)

static func dim_torque() -> Dictionary:
	return dim(2, 1, -2)

static func dim_angular_velocity() -> Dictionary:
	return dim(0, 0, -1)

static func dim_force() -> Dictionary:
	return dim(1, 1, -2)

static func dim_velocity() -> Dictionary:
	return dim(1, 0, -1)

static func dim_pressure() -> Dictionary:
	return dim(-1, 1, -2)

static func dim_volume_flow() -> Dictionary:
	return dim(3, 0, -1)

static func dim_mul(a: Dictionary, b: Dictionary) -> Dictionary:
	var result := {}
	for key in DIMENSION_KEYS:
		result[key] = int(a.get(key, 0)) + int(b.get(key, 0))
	return result

static func dim_div(a: Dictionary, b: Dictionary) -> Dictionary:
	var result := {}
	for key in DIMENSION_KEYS:
		result[key] = int(a.get(key, 0)) - int(b.get(key, 0))
	return result

static func dim_pow(a: Dictionary, exponent: int) -> Dictionary:
	var result := {}
	for key in DIMENSION_KEYS:
		result[key] = int(a.get(key, 0)) * exponent
	return result

static func dim_equal(a: Dictionary, b: Dictionary) -> bool:
	for key in DIMENSION_KEYS:
		if int(a.get(key, 0)) != int(b.get(key, 0)):
			return false
	return true

static func dim_string(dimension: Dictionary) -> String:
	var parts: Array[String] = []
	for key in DIMENSION_KEYS:
		var exponent := int(dimension.get(key, 0))
		if exponent != 0:
			parts.append("%s^%d" % [String(key), exponent])
	return "1" if parts.is_empty() else " ".join(parts)

# -----------------------------------------------------------------------------
# Network + domain registration.
# -----------------------------------------------------------------------------

static func new_network() -> Dictionary:
	return {
		"domains": {},
		"elements": {},
		"bonds": [],
		"cells": [],
		"diagnostics": [],
		"solve_revision": 0,
		"solver_stats": {},
	}

static func register_domain(
	network: Dictionary,
	domain_id: String,
	common_quantity: String,
	balance_quantity: String,
	common_dimension: Dictionary,
	balance_dimension: Dictionary,
	common_unit: String = "",
	balance_unit: String = "",
	common_nominal: float = 1.0,
	balance_nominal: float = 1.0
) -> bool:
	if domain_id.is_empty() or network["domains"].has(domain_id):
		return false
	if common_quantity.is_empty() or balance_quantity.is_empty():
		return false
	if common_nominal <= 0.0 or balance_nominal <= 0.0:
		return false
	var common_dim := _normalize_dimension(common_dimension)
	var balance_dim := _normalize_dimension(balance_dimension)
	if not dim_equal(dim_mul(common_dim, balance_dim), dim_power()):
		network["diagnostics"].append({
			"code": "DOMAIN_NOT_POWER_CONJUGATE",
			"domain": domain_id,
			"common_dimension": dim_string(common_dim),
			"balance_dimension": dim_string(balance_dim),
			"product_dimension": dim_string(dim_mul(common_dim, balance_dim)),
		})
		return false
	network["domains"][domain_id] = {
		"common_quantity": common_quantity,
		"balance_quantity": balance_quantity,
		"common_dimension": common_dim,
		"balance_dimension": balance_dim,
		"common_unit": common_unit,
		"balance_unit": balance_unit,
		"common_nominal": common_nominal,
		"balance_nominal": balance_nominal,
	}
	return true

# -----------------------------------------------------------------------------
# Generic physical elements.
# -----------------------------------------------------------------------------

static func equilibrium_terminal(
	element_id: String,
	domain: String,
	preferred_common: float,
	response_gain: float
) -> Dictionary:
	assert(response_gain >= 0.0)
	return _physical_element(
		element_id,
		{
			"op": "equilibrium_terminal",
			"preferred_common": preferred_common,
			"response_gain": response_gain,
		},
		{"p": domain},
	)

static func fixed_balance_terminal(element_id: String, domain: String, balance: float) -> Dictionary:
	return _physical_element(
		element_id,
		{"op": "fixed_balance_terminal", "balance": balance},
		{"p": domain},
	)

static func ideal_common_constraint(element_id: String, domain: String, common: float) -> Dictionary:
	return _physical_element(
		element_id,
		{"op": "ideal_common_constraint", "common": common},
		{"p": domain},
	)

static func linear_difference_coupler(element_id: String, domain: String, response_gain: float) -> Dictionary:
	assert(response_gain >= 0.0)
	return _physical_element(
		element_id,
		{"op": "linear_difference_coupler", "response_gain": response_gain},
		{"a": domain, "b": domain},
	)

static func linear_storage_terminal(
	element_id: String,
	domain: String,
	capacity: float,
	initial_common: float = 0.0
) -> Dictionary:
	assert(capacity > EPSILON)
	var result := _physical_element(
		element_id,
		{"op": "linear_storage_terminal", "capacity": capacity},
		{"p": domain},
	)
	result["state"]["common"] = initial_common
	result["state"]["energy"] = 0.0
	result["state"]["last_delta_energy"] = 0.0
	result["state"]["last_absorbed_work"] = 0.0
	result["state"]["last_numerical_dissipation"] = 0.0
	return result

# A row is: {"terms": [{"port": "e", "coefficient": 1.0,
#                        "coefficient_dimension": dim_dimensionless()}, ...],
#            "nominal": 1.0}
# Every coefficient * port-common must have the same row dimension.
static func linear_power_map(
	element_id: String,
	port_domains: Dictionary,
	constraint_rows: Array
) -> Dictionary:
	assert(port_domains.size() >= 2)
	assert(not constraint_rows.is_empty())
	var result := _physical_element(
		element_id,
		{"op": "linear_power_map", "constraint_rows": constraint_rows.duplicate(true)},
		port_domains,
	)
	result["state"]["constraint_lambdas"] = []
	return result

# Nonlinear constitutive element. Every physical port gets an unknown balance.
# residuals must be square: one residual equation per port-balance unknown.
# Each residual is {"expr": <expression AST>, "nominal": positive_number}.
static func nonlinear_constitutive(
	element_id: String,
	port_domains: Dictionary,
	parameters: Dictionary,
	residuals: Array
) -> Dictionary:
	var result := _physical_element(
		element_id,
		{
			"op": "nonlinear_constitutive",
			"parameters": parameters.duplicate(true),
			"residuals": residuals.duplicate(true),
		},
		port_domains,
	)
	result["state"]["newton_balance_guess"] = {}
	return result

# -----------------------------------------------------------------------------
# Dimension-aware expression DSL.
# -----------------------------------------------------------------------------

static func expr_constant(value: float, dimension: Dictionary = {}) -> Dictionary:
	return {"op": "constant", "value": value, "dimension": _normalize_dimension(dimension)}

static func expr_parameter(name: String) -> Dictionary:
	return {"op": "parameter", "name": name}

static func expr_common(port_name: String) -> Dictionary:
	return {"op": "common", "port": port_name}

static func expr_balance(port_name: String) -> Dictionary:
	return {"op": "balance", "port": port_name}

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

static func expr_exp(a: Dictionary) -> Dictionary:
	return {"op": "exp", "a": a}

static func expr_tanh(a: Dictionary) -> Dictionary:
	return {"op": "tanh", "a": a}

# -----------------------------------------------------------------------------
# Graph mutation.
# -----------------------------------------------------------------------------

static func add_element(network: Dictionary, element: Dictionary) -> bool:
	var element_id := String(element.get("id", ""))
	if element_id.is_empty() or network["elements"].has(element_id):
		return false
	var ports: Dictionary = element.get("ports", {})
	if ports.is_empty():
		return false
	for port_name in ports.keys():
		var spec: Dictionary = ports[port_name]
		if String(spec.get("direction", "")) != "physical":
			return false
		var domain := String(spec.get("domain", ""))
		if not network["domains"].has(domain):
			return false
	var copy: Dictionary = element.duplicate(true)
	var validation := _validate_element_dimensions(network, copy)
	if not bool(validation.get("ok", false)):
		var diagnostic: Dictionary = validation.duplicate(true)
		diagnostic["element_id"] = element_id
		network["diagnostics"].append(diagnostic)
		return false
	network["elements"][element_id] = copy
	return true

static func link_ports(
	network: Dictionary,
	bond_id: String,
	element_a: String,
	port_a: String,
	element_b: String,
	port_b: String
) -> bool:
	if bond_id.is_empty() or _find_bond_index(network, bond_id) >= 0:
		return false
	if not network["elements"].has(element_a) or not network["elements"].has(element_b):
		return false
	var spec_a: Dictionary = network["elements"][element_a]["ports"].get(port_a, {})
	var spec_b: Dictionary = network["elements"][element_b]["ports"].get(port_b, {})
	if spec_a.is_empty() or spec_b.is_empty():
		return false
	if String(spec_a.get("direction", "")) != "physical" or String(spec_b.get("direction", "")) != "physical":
		return false
	if String(spec_a.get("domain", "")) != String(spec_b.get("domain", "")):
		return false
	var ref_a := _port_ref(element_a, port_a)
	var ref_b := _port_ref(element_b, port_b)
	if ref_a == ref_b:
		return false
	network["bonds"].append({
		"id": bond_id,
		"a_element": element_a,
		"a_port": port_a,
		"b_element": element_b,
		"b_port": port_b,
		"domain": String(spec_a["domain"]),
		"active": true,
	})
	return true

static func set_bond_active(network: Dictionary, bond_id: String, active: bool) -> bool:
	var index := _find_bond_index(network, bond_id)
	if index < 0:
		return false
	network["bonds"][index]["active"] = active
	return true

# -----------------------------------------------------------------------------
# Solve/read API.
# -----------------------------------------------------------------------------

static func solve(network: Dictionary) -> Dictionary:
	return _solve_network(network, 0.0, false)

static fun