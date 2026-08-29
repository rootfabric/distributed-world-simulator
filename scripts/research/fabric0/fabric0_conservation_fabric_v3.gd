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

static func step(network: Dictionary, delta: float) -> Dictionary:
	assert(delta > 0.0)
	return _solve_network(network, delta, true)

static func read_port_state(network: Dictionary, element_id: String, port_name: String) -> Dictionary:
	if not network["elements"].has(element_id):
		return {}
	return network["elements"][element_id]["state"]["ports"].get(port_name, {}).duplicate(true)

static func read_element_absorbed_power(network: Dictionary, element_id: String) -> float:
	if not network["elements"].has(element_id):
		return 0.0
	return float(network["elements"][element_id]["state"].get("absorbed_power", 0.0))

static func read_element_state(network: Dictionary, element_id: String, key: String) -> Variant:
	if not network["elements"].has(element_id):
		return null
	return network["elements"][element_id]["state"].get(key)

static func max_balance_residual(network: Dictionary) -> float:
	var result := 0.0
	for cell in network["cells"]:
		result = maxf(result, absf(float(cell.get("balance_residual", 0.0))))
	return result

static func max_power_residual(network: Dictionary) -> float:
	var result := 0.0
	for cell in network["cells"]:
		result = maxf(result, absf(float(cell.get("power_residual", 0.0))))
	return result

static func total_absorbed_power(network: Dictionary) -> float:
	var result := 0.0
	for element in network["elements"].values():
		result += float(element["state"].get("absorbed_power", 0.0))
	return result

static func state_hash(network: Dictionary) -> String:
	var payload := JSON.stringify(canonical_snapshot(network), "", false)
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(payload.to_utf8_buffer())
	return context.finish().hex_encode()

static func canonical_snapshot(network: Dictionary) -> Dictionary:
	var domain_ids: Array = network["domains"].keys()
	domain_ids.sort()
	var domains := {}
	for domain_id in domain_ids:
		domains[domain_id] = _sorted_dictionary(network["domains"][domain_id])
	var element_ids: Array = network["elements"].keys()
	element_ids.sort()
	var elements: Array = []
	for element_id in element_ids:
		var element: Dictionary = network["elements"][element_id]
		elements.append({
			"id": element_id,
			"law": _sorted_dictionary(element["law"]),
			"ports": _sorted_dictionary(element["ports"]),
			"state": _sorted_dictionary(element["state"]),
		})
	var bonds: Array = []
	for bond in network["bonds"]:
		bonds.append(_sorted_dictionary(bond))
	bonds.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["id"]) < String(b["id"]))
	var cells: Array = []
	for cell in network["cells"]:
		cells.append(_sorted_dictionary(cell))
	cells.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["id"]) < String(b["id"]))
	var diagnostics: Array = []
	for diagnostic in network["diagnostics"]:
		diagnostics.append(_sorted_dictionary(diagnostic))
	return {
		"domains": domains,
		"elements": elements,
		"bonds": bonds,
		"cells": cells,
		"diagnostics": diagnostics,
		"solver_stats": _sorted_dictionary(network.get("solver_stats", {})),
	}

# -----------------------------------------------------------------------------
# Dimension validation.
# -----------------------------------------------------------------------------

static func _validate_element_dimensions(network: Dictionary, element: Dictionary) -> Dictionary:
	var op := String(element["law"].get("op", ""))
	match op:
		"equilibrium_terminal", "fixed_balance_terminal", "ideal_common_constraint", "linear_storage_terminal":
			return {"ok": true}
		"linear_difference_coupler":
			var a_domain := String(element["ports"]["a"]["domain"])
			var b_domain := String(element["ports"]["b"]["domain"])
			if a_domain != b_domain:
				return {"ok": false, "code": "DIFFERENCE_COUPLER_DOMAIN_MISMATCH"}
			return {"ok": true}
		"linear_power_map":
			return _validate_power_map_dimensions(network, element)
		"nonlinear_constitutive":
			return _validate_nonlinear_dimensions(network, element)
		_:
			return {"ok": false, "code": "UNKNOWN_PHYSICAL_LAW", "op": op}

static func _validate_power_map_dimensions(network: Dictionary, element: Dictionary) -> Dictionary:
	var rows: Array = element["law"].get("constraint_rows", [])
	if rows.is_empty():
		return {"ok": false, "code": "POWER_MAP_EMPTY"}
	var used_ports := {}
	var normalized_rows: Array = []
	for row_index in range(rows.size()):
		var row: Dictionary = rows[row_index]
		var terms: Array = row.get("terms", [])
		var nominal := float(row.get("nominal", 0.0))
		if nominal <= 0.0 or terms.size() < 2:
			return {"ok": false, "code": "POWER_MAP_BAD_ROW", "row": row_index}
		var row_dimension: Dictionary = {}
		var normalized_terms: Array = []
		var seen := {}
		for term in terms:
			var port_name := String(term.get("port", ""))
			if not element["ports"].has(port_name) or seen.has(port_name):
				return {"ok": false, "code": "POWER_MAP_BAD_PORT", "row": row_index, "port": port_name}
			seen[port_name] = true
			used_ports[port_name] = true
			if not term.has("coefficient_dimension"):
				return {"ok": false, "code": "POWER_MAP_MISSING_COEFFICIENT_DIMENSION", "row": row_index, "port": port_name}
			var coefficient_dimension := _normalize_dimension(term["coefficient_dimension"])
			var domain_id := String(element["ports"][port_name]["domain"])
			var common_dimension: Dictionary = network["domains"][domain_id]["common_dimension"]
			var term_dimension := dim_mul(coefficient_dimension, common_dimension)
			if row_dimension.is_empty():
				row_dimension = term_dimension
			elif not dim_equal(row_dimension, term_dimension):
				return {
					"ok": false,
					"code": "POWER_MAP_ROW_DIMENSION_MISMATCH",
					"row": row_index,
					"port": port_name,
					"expected": dim_string(row_dimension),
					"actual": dim_string(term_dimension),
				}
			var lambda_dimension := dim_div(dim_power(), row_dimension)
			var expected_balance: Dictionary = network["domains"][domain_id]["balance_dimension"]
			var reaction_dimension := dim_mul(coefficient_dimension, lambda_dimension)
			if not dim_equal(reaction_dimension, expected_balance):
				return {"ok": false, "code": "POWER_MAP_REACTION_DIMENSION_MISMATCH", "row": row_index, "port": port_name}
			normalized_terms.append({
				"port": port_name,
				"coefficient": float(term.get("coefficient", 0.0)),
				"coefficient_dimension": coefficient_dimension,
			})
		normalized_rows.append({
			"terms": normalized_terms,
			"nominal": nominal,
			"row_dimension": row_dimension,
			"lambda_dimension": dim_div(dim_power(), row_dimension),
		})
	if used_ports.size() != element["ports"].size():
		return {"ok": false, "code": "POWER_MAP_UNUSED_PORT"}
	element["law"]["constraint_rows"] = normalized_rows
	return {"ok": true}

static func _validate_nonlinear_dimensions(network: Dictionary, element: Dictionary) -> Dictionary:
	var parameters: Dictionary = element["law"].get("parameters", {})
	for parameter_name in parameters.keys():
		var parameter: Dictionary = parameters[parameter_name]
		if not parameter.has("value") or not parameter.has("dimension"):
			return {"ok": false, "code": "NONLINEAR_BAD_PARAMETER", "parameter": String(parameter_name)}
		parameter["value"] = float(parameter["value"])
		parameter["dimension"] = _normalize_dimension(parameter["dimension"])
	var residuals: Array = element["law"].get("residuals", [])
	if residuals.size() != element["ports"].size():
		return {
			"ok": false,
			"code": "NONLINEAR_RESIDUAL_COUNT_MISMATCH",
			"ports": element["ports"].size(),
			"residuals": residuals.size(),
		}
	var normalized_residuals: Array = []
	for residual_index in range(residuals.size()):
		var spec: Dictionary = residuals[residual_index]
		var nominal := float(spec.get("nominal", 0.0))
		if nominal <= 0.0 or not spec.has("expr"):
			return {"ok": false, "code": "NONLINEAR_BAD_RESIDUAL", "residual": residual_index}
		var inferred := _infer_expr_dimension(network, element, spec["expr"])
		if not bool(inferred.get("ok", false)):
			var diagnostic: Dictionary = inferred.duplicate(true)
			diagnostic["code"] = "NONLINEAR_DIMENSION_ERROR"
			diagnostic["residual"] = residual_index
			return diagnostic
		normalized_residuals.append({
			"expr": spec["expr"].duplicate(true),
			"nominal": nominal,
			"dimension": inferred["dimension"],
		})
	element["law"]["parameters"] = parameters
	element["law"]["residuals"] = normalized_residuals
	return {"ok": true}

static func _infer_expr_dimension(network: Dictionary, element: Dictionary, expr: Dictionary) -> Dictionary:
	var op := String(expr.get("op", ""))
	match op:
		"constant":
			return {"ok": true, "dimension": _normalize_dimension(expr.get("dimension", {}))}
		"parameter":
			var name := String(expr.get("name", ""))
			var parameters: Dictionary = element["law"].get("parameters", {})
			if not parameters.has(name):
				return {"ok": false, "reason": "UNKNOWN_PARAMETER", "name": name}
			return {"ok": true, "dimension": _normalize_dimension(parameters[name]["dimension"])}
		"common", "balance":
			var port_name := String(expr.get("port", ""))
			if not element["ports"].has(port_name):
				return {"ok": false, "reason": "UNKNOWN_PORT", "port": port_name}
			var domain_id := String(element["ports"][port_name]["domain"])
			var key := "common_dimension" if op == "common" else "balance_dimension"
			return {"ok": true, "dimension": network["domains"][domain_id][key]}
		"add", "sub":
			var left := _infer_expr_dimension(network, element, expr["a"])
			if not bool(left.get("ok", false)):
				return left
			var right := _infer_expr_dimension(network, element, expr["b"])
			if not bool(right.get("ok", false)):
				return right
			if not dim_equal(left["dimension"], right["dimension"]):
				return {
					"ok": false,
					"reason": "ADD_SUB_DIMENSION_MISMATCH",
					"left": dim_string(left["dimension"]),
					"right": dim_string(right["dimension"]),
				}
			return {"ok": true, "dimension": left["dimension"]}
		"mul", "div":
			var left := _infer_expr_dimension(network, element, expr["a"])
			if not bool(left.get("ok", false)):
				return left
			var right := _infer_expr_dimension(network, element, expr["b"])
			if not bool(right.get("ok", false)):
				return right
			return {
				"ok": true,
				"dimension": dim_mul(left["dimension"], right["dimension"]) if op == "mul" else dim_div(left["dimension"], right["dimension"]),
			}
		"neg":
			return _infer_expr_dimension(network, element, expr["a"])
		"pow_int":
			var child := _infer_expr_dimension(network, element, expr["a"])
			if not bool(child.get("ok", false)):
				return child
			return {"ok": true, "dimension": dim_pow(child["dimension"], int(expr.get("exponent", 1)))}
		"exp", "tanh":
			var child := _infer_expr_dimension(network, element, expr["a"])
			if not bool(child.get("ok", false)):
				return child
			if not dim_equal(child["dimension"], dim_dimensionless()):
				return {
					"ok": false,
					"reason": "TRANSCENDENTAL_REQUIRES_DIMENSIONLESS",
					"actual": dim_string(child["dimension"]),
				}
			return {"ok": true, "dimension": dim_dimensionless()}
		_:
			return {"ok": false, "reason": "UNKNOWN_EXPRESSION_OP", "op": op}

# -----------------------------------------------------------------------------
# Topology compilation + Newton solve.
# -----------------------------------------------------------------------------

static func _solve_network(network: Dictionary, delta: float, commit_dynamic: bool) -> Dictionary:
	network["diagnostics"] = []
	network["cells"] = []
	network["solver_stats"] = {}
	var previous_port_states := _capture_port_states(network)
	_reset_port_states(network)
	var compiled := _compile_cells(network)
	if not bool(compiled.get("ok", false)):
		network["diagnostics"].append(compiled)
		network["solve_revision"] = int(network.get("solve_revision", 0)) + 1
		return {"ok": false, "diagnostics": network["diagnostics"].duplicate(true)}
	var cell_map: Dictionary = compiled["cell_map"]
	network["cells"] = compiled["cells"]
	var islands := _compile_is