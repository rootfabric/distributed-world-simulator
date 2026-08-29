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
	var islands := _compile_islands(network, cell_map)
	var all_ok := true
	var total_iterations := 0
	var worst_normalized_residual := 0.0
	for island in islands:
		var result := _solve_island_newton(network, cell_map, island, delta, previous_port_states)
		total_iterations += int(result.get("iterations", 0))
		worst_normalized_residual = maxf(worst_normalized_residual, float(result.get("normalized_residual", 0.0)))
		if not bool(result.get("ok", false)):
			all_ok = false
	if all_ok and commit_dynamic:
		_commit_dynamic_state(network, delta)
	network["solver_stats"] = {
		"islands": islands.size(),
		"total_iterations": total_iterations,
		"max_normalized_residual": worst_normalized_residual,
	}
	network["solve_revision"] = int(network.get("solve_revision", 0)) + 1
	return {
		"ok": all_ok,
		"cell_count": network["cells"].size(),
		"island_count": islands.size(),
		"iterations": total_iterations,
		"normalized_residual": worst_normalized_residual,
		"diagnostics": network["diagnostics"].duplicate(true),
	}

static func _compile_cells(network: Dictionary) -> Dictionary:
	var port_refs: Array = []
	var port_domains := {}
	var element_ids: Array = network["elements"].keys()
	element_ids.sort()
	for element_id in element_ids:
		var ports: Dictionary = network["elements"][element_id]["ports"]
		var port_names: Array = ports.keys()
		port_names.sort()
		for port_name in port_names:
			var ref := _port_ref(element_id, String(port_name))
			port_refs.append(ref)
			port_domains[ref] = String(ports[port_name]["domain"])
	var adjacency := {}
	for ref in port_refs:
		adjacency[ref] = []
	for bond in network["bonds"]:
		if not bool(bond.get("active", false)):
			continue
		var a := _port_ref(String(bond["a_element"]), String(bond["a_port"]))
		var b := _port_ref(String(bond["b_element"]), String(bond["b_port"]))
		if not adjacency.has(a) or not adjacency.has(b):
			return {"ok": false, "code": "BROKEN_BOND_ENDPOINT", "bond_id": String(bond["id"])}
		adjacency[a].append(b)
		adjacency[b].append(a)
	var visited := {}
	var cells: Array = []
	var cell_map := {}
	for root in port_refs:
		if visited.has(root):
			continue
		var queue: Array = [root]
		var component: Array = []
		visited[root] = true
		while not queue.is_empty():
			var current: String = queue.pop_front()
			component.append(current)
			var neighbours: Array = adjacency[current]
			neighbours.sort()
			for neighbour in neighbours:
				if not visited.has(neighbour):
					visited[neighbour] = true
					queue.append(neighbour)
		component.sort()
		var domain := String(port_domains[component[0]])
		for ref in component:
			if String(port_domains[ref]) != domain:
				return {"ok": false, "code": "MIXED_DOMAIN_CELL", "ports": component}
		var cell_index := cells.size()
		var cell_id := "cell/%s/%s" % [domain, String(component[0])]
		cells.append({
			"id": cell_id,
			"domain": domain,
			"ports": component,
			"common": 0.0,
			"balance_residual": 0.0,
			"power_residual": 0.0,
			"status": "UNSOLVED",
		})
		for ref in component:
			cell_map[ref] = cell_index
	return {"ok": true, "cells": cells, "cell_map": cell_map}

static func _compile_islands(network: Dictionary, cell_map: Dictionary) -> Array:
	var adjacency := {}
	for cell_index in range(network["cells"].size()):
		adjacency[cell_index] = []
	var element_ids: Array = network["elements"].keys()
	element_ids.sort()
	for element_id in element_ids:
		var element: Dictionary = network["elements"][element_id]
		var indices: Array = []
		var port_names: Array = element["ports"].keys()
		port_names.sort()
		for port_name in port_names:
			var cell_index := int(cell_map[_port_ref(element_id, String(port_name))])
			if cell_index not in indices:
				indices.append(cell_index)
		indices.sort()
		for left in range(indices.size()):
			for right in range(left + 1, indices.size()):
				var a := int(indices[left])
				var b := int(indices[right])
				if b not in adjacency[a]:
					adjacency[a].append(b)
				if a not in adjacency[b]:
					adjacency[b].append(a)
	var visited := {}
	var islands: Array = []
	for root in range(network["cells"].size()):
		if visited.has(root):
			continue
		var queue: Array = [root]
		var island: Array = []
		visited[root] = true
		while not queue.is_empty():
			var current: int = queue.pop_front()
			island.append(current)
			var neighbours: Array = adjacency[current]
			neighbours.sort()
			for neighbour in neighbours:
				if not visited.has(neighbour):
					visited[neighbour] = true
					queue.append(neighbour)
		island.sort()
		islands.append(island)
	islands.sort_custom(func(a: Array, b: Array) -> bool:
		return String(network["cells"][a[0]]["id"]) < String(network["cells"][b[0]]["id"])
	)
	return islands

static func _solve_island_newton(
	network: Dictionary,
	cell_map: Dictionary,
	island: Array,
	delta: float,
	previous_port_states: Dictionary
) -> Dictionary:
	var model := _build_island_model(network, cell_map, island, delta, previous_port_states)
	if not bool(model.get("ok", false)):
		_mark_island_failed(network, island, String(model.get("code", "MODEL_BUILD_FAILED")))
		network["diagnostics"].append(model)
		return model
	var x: Array = model["initial_x"]
	var last_norm := INF
	var converged := false
	var iterations := 0
	for iteration in range(NEWTON_MAX_ITERATIONS):
		iterations = iteration + 1
		var assembled := _assemble_residual_jacobian(network, model, x, delta)
		if not bool(assembled.get("ok", false)):
			_mark_island_failed(network, island, String(assembled.get("code", "NONLINEAR_EVALUATION_FAILED")))
			network["diagnostics"].append(assembled)
			return {"ok": false, "iterations": iterations, "normalized_residual": last_norm, "code": assembled.get("code", "NONLINEAR_EVALUATION_FAILED")}
		var norm := _normalized_residual_norm(assembled["residual"], model["row_nominals"])
		last_norm = norm
		if norm <= NEWTON_TOLERANCE:
			# A zero residual is not enough: an underdetermined/floating island can
			# satisfy F(x)=0 at infinitely many x. Require a nonsingular tangent.
			var rank_probe := _solve_dense(assembled["jacobian"], _zero_vector(x.size()))
			if not bool(rank_probe.get("ok", false)):
				var rank_code := "SINGULAR_FLOATING_ISLAND" if model["constraints"].is_empty() and model["nonlinear_elements"].is_empty() else "SINGULAR_SOLUTION_MANIFOLD"
				var rank_failure := {
					"ok": false,
					"code": rank_code,
					"cells": _cell_ids(network, island),
					"iteration": iterations,
					"normalized_residual": norm,
				}
				_mark_island_failed(network, island, rank_code)
				network["diagnostics"].append(rank_failure)
				return rank_failure
			converged = true
			break
		var rhs: Array = []
		for value in assembled["residual"]:
			rhs.append(-float(value))
		var step_result := _solve_dense(assembled["jacobian"], rhs)
		if not bool(step_result.get("ok", false)):
			var singular_code := "SINGULAR_FLOATING_ISLAND" if model["constraints"].is_empty() and model["nonlinear_elements"].is_empty() else "NEWTON_SINGULAR_JACOBIAN"
			var singular := {
				"ok": false,
				"code": singular_code,
				"cells": _cell_ids(network, island),
				"iteration": iterations,
				"normalized_residual": norm,
			}
			_mark_island_failed(network, island, String(singular["code"]))
			network["diagnostics"].append(singular)
			return singular
		var dx: Array = step_result["x"]
		var max_scaled_step := 0.0
		for index in range(dx.size()):
			var nominal := float(model["unknown_nominals"][index])
			max_scaled_step = maxf(max_scaled_step, absf(float(dx[index])) / maxf(nominal, EPSILON))
		var accepted := false
		var alpha := 1.0
		for _line_search in range(NEWTON_MAX_LINE_SEARCH):
			var candidate := x.duplicate()
			for index in range(candidate.size()):
				candidate[index] = float(candidate[index]) + alpha * float(dx[index])
			var candidate_assembled := _assemble_residual_jacobian(network, model, candidate, delta)
			if bool(candidate_assembled.get("ok", false)):
				var candidate_norm := _normalized_residual_norm(candidate_assembled["residual"], model["row_nominals"])
				if candidate_norm < norm or candidate_norm <= NEWTON_TOLERANCE:
					x = candidate
					last_norm = candidate_norm
					accepted = true
					break
			alpha *= 0.5
		if not accepted:
			var line_fail := {
				"ok": false,
				"code": "NEWTON_LINE_SEARCH_FAILED",
				"cells": _cell_ids(network, island),
				"iteration": iterations,
				"normalized_residual": norm,
			}
			_mark_island_failed(network, island, String(line_fail["code"]))
			network["diagnostics"].append(line_fail)
			return line_fail
	if not converged:
		var failure := {
			"ok": false,
			"code": "NEWTON_NO_CONVERGENCE",
			"cells": _cell_ids(network, island),
			"iterations": iterations,
			"normalized_residual": last_norm,
		}
		_mark_island_failed(network, island, String(failure["code"]))
		network["diagnostics"].append(failure)
		return failure
	_apply_solution(network, model, x, delta)
	_compute_cell_residuals(network, island)
	return {"ok": true, "iterations": iterations, "normalized_residual": last_norm}

static func _build_island_model(
	network: Dictionary,
	cell_map: Dictionary,
	island: Array,
	delta: float,
	previous_port_states: Dictionary
) -> Dictionary:
	var local_cell_unknown := {}
	var unknown_nominals: Array = []
	var initial_x: Array = []
	for local in range(island.size()):
		var global_cell := int(island[local])
		local_cell_unknown[global_cell] = initial_x.size()
		var domain_id := String(network["cells"][global_cell]["domain"])
		var domain: Dictionary = network["domains"][domain_id]
		initial_x.append(_initial_cell_guess(network, global_cell, previous_port_states))
		unknown_nominals.append(float(domain["common_nominal"]))

	var constraints: Array = []
	var nonlinear_balance_indices := {}
	var nonlinear_elements: Array = []
	var element_ids: Array = network["elements"].keys()
	element_ids.sort()
	for element_id in element_ids:
		var element: Dictionary = network["elements"][element_id]
		var port_names: Array = element["ports"].keys()
		port_names.sort()
		var global_cells: Array = []
		for port_name in port_names:
			var global_cell := int(cell_map[_port_ref(element_id, String(port_name))])
			if global_cell in island:
				global_cells.append(global_cell)
		if global_cells.is_empty():
			continue
		if global_cells.size() != port_names.size():
			return {"ok": false, "code": "ELEMENT_SPLIT_ACROSS_SOLVE_ISLAND", "element_id": element_id}
		var op := String(element["law"].get("op", ""))
		match op:
			"linear_difference_coupler":
				var a_domain := String(element["ports"]["a"]["domain"])
				var b_domain := String(element["ports"]["b"]["domain"])
				if a_domain != b_domain:
					return {"ok": false, "code": "DIFFERENCE_COUPLER_DOMAIN_MISMATCH", "element_id": element_id}
			"ideal_common_constraint":
				var global_cell := int(global_cells[0])
				var domain_id := String(network["cells"][global_cell]["domain"])
				constraints.append({
					"kind": "ideal_common",
					"element_id": element_id,
					"row_index": 0,
					"value": float(element["law"].get("common", 0.0)),
					"nominal": float(network["domains"][domain_id]["common_nominal"]),
					"terms": [{
						"cell": int(local_cell_unknown[global_cell]),
						"global_cell": global_cell,
						"port_name": "p",
						"coefficient": 1.0,
					}],
				})
			"linear_power_map":
				var rows: Array = element["law"].get("constraint_rows", [])
				for row_index in range(rows.size()):
					var row: Dictionary = rows[row_index]
					var terms: Array = []
					for term in row["terms"]:
						var port_name := String(term["port"])
						var global_cell := int(cell_map[_port_ref(element_id, port_name)])
						terms.append({
							"cell": int(local_cell_unknown[global_cell]),
							"global_cell": global_cell,
							"port_name": port_name,
							"coefficient": float(term["coefficient"]),
						})
					constraints.append({
						"kind": "power_map",
						"element_id": element_id,
						"row_index": row_index,
						"value": 0.0,
						"nominal": float(row["nominal"]),
						"terms": terms,
					})
			"linear_storage_terminal":
				if delta <= 0.0:
					return {"ok": false, "code": "DYNAMIC_ELEMENT_REQUIRES_STEP", "element_id": element_id}
			"nonlinear_constitutive":
				nonlinear_elements.append(element_id)
				for port_name in port_names:
					var global_cell := int(cell_map[_port_ref(element_id, String(port_name))])
					var domain_id := String(network["cells"][global_cell]["domain"])
					var key := _port_ref(element_id, String(port_name))
					nonlinear_balance_indices[key] = initial_x.size()
					var previous_balance := float(previous_port_states.get(key, {}).get("balance", 0.0))
					initial_x.append(previous_balance)
					unknown_nominals.append(float(network["domains"][domain_id]["balance_nominal"]))

	var constraint_check := _validate_constraint_conflicts(network, constraints)
	if not bool(constraint_check.get("ok", false)):
		return constraint_check

	# Lambda unknowns are appended after q and nonlinear balances. Their numeric
	# nominal is inferred from power / row quantity only for scaling purposes;
	# use 1.0 because coherent-SI values are already normalized by row residuals.
	for constraint_index in range(constraints.size()):
		constraints[constraint_index]["lambda_unknown"] = initial_x.size()
		initial_x.append(0.0)
		unknown_nominals.append(1.0)

	var row_nominals: Array = []
	for global_cell in island:
		var domain_id := String(network["cells"][global_cell]["domain"])
		row_nominals.append(float(network["domains"][domain_id]["balance_nominal"]))
	for constraint in constraints:
		row_nominals.append(float(constraint["nominal"]))
	for element_id in nonlinear_elements:
		var element: Dictionary = network["elements"][element_id]
		for residual in element["law"]["residuals"]:
			row_nominals.append(float(residual["nominal"]))

	if row_nominals.size() != initial_x.size():
		return {
			"ok": false,
			"code": "NON_SQUARE_ISLAND_MODEL",
			"unknowns": initial_x.size(),
			"equations": row_nominals.size(),
		}

	return {
		"ok": true,
		"island": island,
		"cell_map": cell_map,
		"local_cell_unknown": local_cell_unknown,
		"constraints": constraints,
		"nonlinear_balance_indices": nonlinear_balance_indices,
		"nonlinear_elements": nonlinear_elements,
		"initial_x": initial_x,
		"unknown_nominals": unknown_nominals,
		"row_nominals": row_nominals,
	}

static func _assemble_residual_jacobian(network: Dictionary, model: Dictionary, x: Array, delta: float) -> Dictionary:
	var size := x.size()
	var residual := _zero_vector(size)
	var jacobian := _zero_matrix(size, size)
	var island: Array = model["island"]
	var cell_map: Dictionary = model["cell_map"]
	var local_cell_unknown: Dictionary = model["local_cell_unknown"]
	var nonlinear_balance_indices: Dictionary = model["nonlinear_balance_indices"]
	var constraints: Array = model["constraints"]

	var element_ids: Array = network["elements"].keys()
	element_ids.sort()
	for element_id in element_ids:
		var element: Dictionary = network["elements"][element_id]
		var port_names: Array = element["ports"].keys()
		port_names.sort()
		var touches := false
		for port_name in port_names:
			if int(cell_map[_port_ref(element_id, String(port_name))]) in island:
				touches = true
				break
		if not touches:
			continue
		var op := String(element["law"].get("op", ""))
		match op:
			"equilibrium_terminal":
				var global_cell := int(cell_map[_port_ref(element_id, "p")])
				var q_index := int(local_cell_unknown[global_cell])
				var g := float(element["law"]["response_gain"])
				var preferred := float(element["law"]["preferred_common"])
				residual[q_index] += g * (preferred - float(x[q_index]))
				jacobian[q_index][q_index] -= g
			"fixed_balance_terminal":
				var global_cell := int(cell_map[_port_ref(element_id, "p")])
				var q_index := int(local_cell_unknown[global_cell])
				residual[q_index] += float(element["law"]["balance"])
			"linear_difference_coupler":
				var a_global := int(cell_map[_port_ref(element_id, "a")])
				var b_global := int(cell_map[_port_ref(element_id, "b")])
				var a := int(local_cell_unknown[a_global])
				var b := int(local_cell_unknown[b_global])
				if a != b:
					var g := float(element["law"]["response_gain"])
					var transfer := g * (float(x[a]) - float(x[b]))
					residual[a] -= transfer
					residual[b] += transfer
					jacobian[a][a] -= g
					jacobian[a][b] += g
					jacobian[b][a] += g
					jacobian[b][b] -= g
			"linear_storage_terminal":
				var global_cell := int(cell_map[_port_ref(element_id, "p")])
				var q_index := int(local_cell_unknown[global_cell])
				var capacity := float(element["law"]["capacity"])
				var previous := float(element["state"].get("common", 0.0))
				var g := capacity / delta
				residual[q_index] += g * (previous - float(x[q_index]))
				jacobian[q_index][q_index] -= g
			"nonlinear_constitutive":
				for port_name in port_names:
					var global_cell := int(cell_map[_port_ref(element_id, String(port_name))])
					var q_index := int(local_cell_unknown[global_cell])
					var balance_index := int(nonlinear_balance_indices[_port_ref(element_id, String(port_name))])
					residual[q_index] += float(x[balance_index])
					jacobian[q_index][balance_index] += 1.0

	for constraint_index in range(constraints.size()):
		var constraint: Dictionary = constraints[constraint_index]
		var lambda_index := int(constraint["lambda_unknown"])
		var lambda := float(x[lambda_index])
		var row := island.size() + constraint_index
		residual[row] -= float(constraint["value"])
		for term in constraint["terms"]:
			var q_index := int(term["cell"])
			var coefficient := float(term["coefficient"])
			residual[q_index] -= coefficient * lambda
			jacobian[q_index][lambda_index] -= coefficient
			residual[row] += coefficient * float(x[q_index])
			jacobian[row][q_index] += coefficient

	var nonlinear_row := island.size() + constraints.size()
	for element_id in model["nonlinear_elements"]:
		var element: Dictionary = network["elements"][element_id]
		for residual_spec in element["law"]["residuals"]:
			var evaluated := _eval_expr_dual(network, element, residual_spec["expr"], model, x)
			if not bool(evaluated.get("ok", false)):
				return evaluated
			residual[nonlinear_row] = float(evaluated["value"])
			for unknown_index in evaluated["grad"].keys():
				jacobian[nonlinear_row][int(unknown_index)] += float(evaluated["grad"][unknown_index])
			nonlinear_row += 1

	return {"ok": true, "residual": residual, "jacobian": jacobian}

static func _eval_expr_dual(network: Dictionary, element: Dictionary, expr: Dictionary, model: Dictionary, x: Array) -> Dictionary:
	var op := String(expr.get("op", ""))
	match op:
		"constant":
			return {"ok": true, "value": float(expr.get("value", 0.0)), "grad": {}}
		"parameter":
			var name := String(expr.get("name", ""))
			return {"ok": true, "value": float(element["law"]["parameters"][name]["value"]), "grad": {}}
		"common":
			var port_name := String(expr.get("port", ""))
			var global_cell := int(model["cell_map"][_port_ref(String(element["id"]), port_name)])
			var index := int(model["local_cell_unknown"][global_cell])
			return {"ok": true, "value": float(x[index]), "grad": {index: 1.0}}
		"balance":
			var port_name := String(expr.get("port", ""))
			var index := int(model["nonlinear_balance_indices"][_port_ref(String(element["id"]), port_name)])
			return {"ok": true, "value": float(x[index]), "grad": {index: 1.0}}
		"neg":
			var a := _eval_expr_dual(network, element, expr["a"], model, x)
			if not bool(a.get("ok", false)):
				return a
			return {"ok": true, "value": -float(a["value"]), "grad": _grad_scaled(a["grad"], -1.0)}
		"add", "sub", "mul", "div":
			var a := _eval_expr_dual(network, element, expr["a"], model, x)
			if not bool(a.get("ok", false)):
				return a
			var b := _eval_expr_dual(network, element, expr["b"], model, x)
			if not bool(b.get("ok", false)):
				return b
			var av := float(a["value"])
			var bv := float(b["value"])
			match op:
				"add":
					return {"ok": true, "value": av + bv, "grad": _grad_combine(a["grad"], 1.0, b["grad"], 1.0)}
				"sub":
					return {"ok": true, "value": av - bv, "grad": _grad_combine(a["grad"], 1.0, b["grad"], -1.0)}
				"mul":
					return {"ok": true, "value": av * bv, "grad": _grad_combine(a["grad"], bv, b["grad"], av)}
				"div":
					if absf(bv) <= 1.0e-15:
						return {"ok": false, "code": "NONLINEAR_DIVISION_BY_ZERO"}
					return {"ok": true, "value": av / bv, "grad": _grad_combine(a["grad"], 1.0 / bv, b["grad"], -av / (bv * bv))}
		"pow_int":
			var a := _eval_expr_dual(network, element, expr["a"], model, x)
			if not bool(a.get("ok", false)):
				return a
			var exponent := int(expr.get("exponent", 1))
			var av := float(a["value"])
			if exponent < 0 and absf(av) <= 1.0e-15:
				return {"ok": false, "code": "NONLINEAR_NEGATIVE_POWER_ZERO"}
			var value := pow(av, exponent)
			var derivative := 0.0 if exponent == 0 else float(exponent) * pow(av, exponent - 1)
			return {"ok": true, "value": value, "grad": _grad_scaled(a["grad"], derivative)}
		"exp":
			var a := _eval_expr_dual(network, element, expr["a"], model, x)
			if not bool(a.get("ok", false)):
				return a
			var av := float(a["value"])
			if av > 700.0:
				return {"ok": false, "code": "NONLINEAR_EXP_OVERFLOW", "argument": av}
			if av < -745.0:
				return {"ok": true, "value": 0.0, "grad": {}}
			var value := exp(av)
			return {"ok": true, "value": value, "grad": _grad_scaled(a["grad"], value)}
		"tanh":
			var a := _eval_expr_dual(network, element, expr["a"], model, x)
			if not bool(a.get("ok", false)):
				return a
			var value := tanh(float(a["value"]))
			return {"ok": true, "value": value, "grad": _grad_scaled(a["grad"], 1.0 - value * value)}
		_:
			return {"ok": false, "code": "UNKNOWN_EXPRESSION_OP", "op": op}
	return {"ok": false, "code": "UNKNOWN_EXPRESSION_OP", "op": op}

static func _apply_solution(network: Dictionary, model: Dictionary, x: Array, delta: float) -> void:
	var island: Array = model["island"]
	var cell_map: Dictionary = model["cell_map"]
	var local_cell_unknown: Dictionary = model["local_cell_unknown"]
	for global_cell in island:
		var q_index := int(local_cell_unknown[int(global_cell)])
		network["cells"][global_cell]["common"] = float(x[q_index])
		network["cells"][global_cell]["status"] = "SOLVED"

	var reactions := {}
	for constraint in model["constraints"]:
		var lambda := float(x[int(constraint["lambda_unknown"])])
		var element_id := String(constraint["element_id"])
		if not reactions.has(element_id):
			reactions[element_id] = {}
		var lambdas: Array = network["elements"][element_id]["state"].get("constraint_lambdas", [])
		while lambdas.size() <= int(constraint["row_index"]):
			lambdas.append(0.0)
		lambdas[int(constraint["row_index"])] = lambda
		network["elements"][element_id]["state"]["constraint_lambdas"] = lambdas
		for term in constraint["terms"]:
			var port_name := String(term["port_name"])
			var reaction := -float(term["coefficient"]) * lambda
			reactions[element_id][port_name] = float(reactions[element_id].get(port_name, 0.0)) + reaction

	var element_ids: Array = network["elements"].keys()
	element_ids.sort()
	for element_id in element_ids:
		var element: Dictionary = network["elements"][element_id]
		var port_names: Array = element["ports"].keys()
		port_names.sort()
		var touches := false
		for port_name in port_names:
			if int(cell_map[_port_ref(element_id, String(port_name))]) in island:
				touches = true
				break
		if not touches:
			continue
		var op := String(element["law"].get("op", ""))
		match op:
			"equilibrium_terminal":
				var global_cell := int(cell_map[_port_ref(element_id, "p")])
				var common := float(x[int(local_cell_unknown[global_cell])])
				var balance := float(element["law"]["response_gain"]) * (float(element["law"]["preferred_common"]) - common)
				_set_port_state(element, "p", common, balance)
			"fixed_balance_terminal":
				var global_cell := int(cell_map[_port_ref(element_id, "p")])
				_set_port_state(element, "p", float(x[int(local_cell_unknown[global_cell])]), float(element["law"]["balance"]))
			"linear_difference_coupler":
				var a_global := int(cell_map[_port_ref(element_id, "a")])
				var b_global := int(cell_map[_port_ref(element_id, "b")])
				var common_a := float(x[int(local_cell_unknown[a_global])])
				var common_b := float(x[int(local_cell_unknown[b_global])])
				var transfer := float(element["law"]["response_gain"]) * (common_a - common_b)
				_set_port_state(element, "a", common_a, -transfer)
				_set_port_state(element, "b", common_b, transfer)
			"ideal_common_constraint", "linear_power_map":
				for port_name in port_names:
					var global_cell := int(cell_map[_port_ref(element_id, String(port_name))])
					var common := float(x[int(local_cell_unknown[global_cell])])
					_set_port_state(element, String(port_name), common, float(reactions.get(element_id, {}).get(port_name, 0.0)))
			"linear_storage_terminal":
				var global_cell := int(cell_map[_port_ref(element_id, "p")])
				var common := float(x[int(local_cell_unknown[global_cell])])
				var capacity := float(element["law"]["capacity"])
				var previous := float(element["state"].get("common", 0.0))
				_set_port_state(element, "p", common, capacity / delta * (previous - common))
			"nonlinear_constitutive":
				for port_name in port_names:
					var global_cell := int(cell_map[_port_ref(element_id, String(port_name))])
					var common := float(x[int(local_cell_unknown[global_cell])])
					var balance_index := int(model["nonlinear_balance_indices"][_port_ref(element_id, String(port_name))])
					_set_port_state(element, String(port_name), common, float(x[balance_index]))

		var power_into_cells := 0.0
		for port_name in port_names:
			power_into_cells += float(element["state"]["ports"][port_name]["power_into_cell"])
		element["state"]["absorbed_power"] = -power_into_cells

static func _commit_dynamic_state(network: Dictionary, delta: float) -> void:
	var element_ids: Array = network["elements"].keys()
	element_ids.sort()
	for element_id in element_ids:
		var element: Dictionary = network["elements"][element_id]
		if String(element["law"].get("op", "")) != "linear_storage_terminal":
			continue
		var previous := float(element["state"].get("common", 0.0))
		var current := float(element["state"]["ports"]["p"]["common"])
		var capacity := float(element["law"]["capacity"])
		var before_energy := 0.5 * capacity * previous * previous
		var after_energy := 0.5 * capacity * current * current
		var absorbed_work := float(element["state"]["absorbed_power"]) * delta
		var delta_energy := after_energy - before_energy
		element["state"]["common"] = current
		element["state"]["energy"] = after_energy
		element["state"]["last_delta_energy"] = delta_energy
		element["state"]["last_absorbed_work"] = absorbed_work
		element["state"]["last_numerical_dissipation"] = absorbed_work - delta_energy

static func _compute_cell_residuals(network: Dictionary, island: Array) -> void:
	for global_cell in island:
		var cell: Dictionary = network["cells"][global_cell]
		var balance := 0.0
		for ref in cell["ports"]:
			var parts := String(ref).split("::", false, 1)
			balance += float(network["elements"][String(parts[0])]["state"]["ports"][String(parts[1])]["balance"])
		cell["balance_residual"] = balance
		cell["power_residual"] = float(cell["common"]) * balance
		cell["status"] = "SOLVED"

# -----------------------------------------------------------------------------
# Solver helpers.
# -----------------------------------------------------------------------------

static func _initial_cell_guess(network: Dictionary, global_cell: int, previous_port_states: Dictionary) -> float:
	var cell: Dictionary = network["cells"][global_cell]
	var domain: Dictionary = network["domains"][String(cell["domain"])]
	var previous_values: Array[float] = []
	for ref in cell["ports"]:
		if previous_port_states.has(ref):
			var value := float(previous_port_states[ref].get("common", 0.0))
			if absf(value) > EPSILON:
				previous_values.append(value)
	if not previous_values.is_empty():
		var sum := 0.0
		for value in previous_values:
			sum += value
		return sum / float(previous_values.size())
	# Prefer explicit storage state where available.
	for ref in cell["ports"]:
		var parts := String(ref).split("::", false, 1)
		var element: Dictionary = network["elements"][String(parts[0])]
		if String(element["law"].get("op", "")) == "linear_storage_terminal":
			return float(element["state"].get("common", 0.0))
	# Weighted equilibrium estimate is an excellent generic seed for static nets.
	var weighted := 0.0
	var weight := 0.0
	for ref in cell["ports"]:
		var parts := String(ref).split("::", false, 1)
		var element: Dictionary = network["elements"][String(parts[0])]
		if String(element["law"].get("op", "")) == "equilibrium_terminal":
			var g := float(element["law"].get("response_gain", 0.0))
			weighted += g * float(element["law"].get("preferred_common", 0.0))
			weight += g
	if weight > EPSILON:
		return weighted / weight
	return float(domain["common_nominal"])

static func _validate_constraint_conflicts(network: Dictionary, constraints: Array) -> Dictionary:
	var by_cell := {}
	for constraint in constraints:
		if String(constraint.get("kind", "")) != "ideal_common":
			continue
		var global_cell := int(constraint["terms"][0]["global_cell"])
		if not by_cell.has(global_cell):
			by_cell[global_cell] = []
		by_cell[global_cell].append(constraint)
	for global_cell in by_cell.keys():
		var items: Array = by_cell[global_cell]
		if items.size() <= 1:
			continue
		var first_value := float(items[0]["value"])
		var element_ids: Array = []
		for item in items:
			element_ids.append(String(item["element_id"]))
			if absf(float(item["value"]) - first_value) > EPSILON:
				return {"ok": false, "code": "CONSTRAINT_CONFLICT", "cell_id": String(network["cells"][global_cell]["id"]), "elements": element_ids}
		return {"ok": false, "code": "REDUNDANT_IDEAL_CONSTRAINT", "cell_id": String(network["cells"][global_cell]["id"]), "elements": element_ids}
	return {"ok": true}

static func _normalized_residual_norm(residual: Array, row_nominals: Array) -> float:
	var result := 0.0
	for index in range(residual.size()):
		result = maxf(result, absf(float(residual[index])) / maxf(float(row_nominals[index]), EPSILON))
	return result

static func _grad_scaled(source: Dictionary, scale: float) -> Dictionary:
	var result := {}
	for key in source.keys():
		result[key] = float(source[key]) * scale
	return result

static func _grad_combine(a: Dictionary, scale_a: float, b: Dictionary, scale_b: float) -> Dictionary:
	var result := {}
	for key in a.keys():
		result[key] = float(result.get(key, 0.0)) + float(a[key]) * scale_a
	for key in b.keys():
		result[key] = float(result.get(key, 0.0)) + float(b[key]) * scale_b
	return result

static func _capture_port_states(network: Dictionary) -> Dictionary:
	var result := {}
	for element_id in network["elements"].keys():
		var element: Dictionary = network["elements"][element_id]
		for port_name in element["state"]["ports"].keys():
			result[_port_ref(String(element_id), String(port_name))] = element["state"]["ports"][port_name].duplicate(true)
	return result

static func _set_port_state(element: Dictionary, port_name: String, common: float, balance: float) -> void:
	element["state"]["ports"][port_name] = {
		"common": common,
		"balance": balance,
		"power_into_cell": common * balance,
	}

static func _mark_island_failed(network: Dictionary, island: Array, code: String) -> void:
	for cell_index in island:
		network["cells"][cell_index]["status"] = code

static func _reset_port_states(network: Dictionary) -> void:
	for element in network["elements"].values():
		element["state"]["absorbed_power"] = 0.0
		if element["state"].has("constraint_lambdas"):
			element["state"]["constraint_lambdas"] = []
		for port_name in element["state"]["ports"].keys():
			element["state"]["ports"][port_name] = {"common": 0.0, "balance": 0.0, "power_into_cell": 0.0}

static func _physical_element(element_id: String, law: Dictionary, port_domains: Dictionary) -> Dictionary:
	var ports := {}
	var port_states := {}
	var port_names: Array = port_domains.keys()
	port_names.sort()
	for port_name in port_names:
		ports[port_name] = {"direction": "physical", "domain": String(port_domains[port_name])}
		port_states[port_name] = {"common": 0.0, "balance": 0.0, "power_into_cell": 0.0}
	return {
		"id": element_id,
		"law": law.duplicate(true),
		"ports": ports,
		"state": {"ports": port_states, "absorbed_power": 0.0},
	}

static func _solve_dense(matrix: Array, rhs: Array) -> Dictionary:
	var size := rhs.size()
	if matrix.size() != size:
		return {"ok": false, "code": "BAD_MATRIX_SHAPE"}
	if size == 0:
		return {"ok": true, "x": []}
	var a: Array = []
	for row in range(size):
		if matrix[row].size() != size:
			return {"ok": false, "code": "BAD_MATRIX_SHAPE"}
		var values: Array = []
		for col in range(size):
			values.append(float(matrix[row][col]))
		a.append(values)
	var b: Array = []
	for value in rhs:
		b.append(float(value))
	for col in range(size):
		var pivot := col
		var pivot_abs := absf(float(a[col][col]))
		for row in range(col + 1, size):
			var candidate := absf(float(a[row][col]))
			if candidate > pivot_abs:
				pivot = row
				pivot_abs = candidate
		if pivot_abs <= PIVOT_EPSILON:
			return {"ok": false, "code": "SINGULAR_MATRIX"}
		if pivot != col:
			var row_tmp = a[col]
			a[col] = a[pivot]
			a[pivot] = row_tmp
			var b_tmp = b[col]
			b[col] = b[pivot]
			b[pivot] = b_tmp
		var pivot_value := float(a[col][col])
		for j in range(col, size):
			a[col][j] = float(a[col][j]) / pivot_value
		b[col] = float(b[col]) / pivot_value
		for row in range(size):
			if row == col:
				continue
			var factor := float(a[row][col])
			if absf(factor) <= EPSILON:
				continue
			for j in range(col, size):
				a[row][j] = float(a[row][j]) - factor * float(a[col][j])
			b[row] = float(b[row]) - factor * float(b[col])
	return {"ok": true, "x": b}

static func _zero_matrix(rows: int, cols: int) -> Array:
	var matrix: Array = []
	for _row in range(rows):
		var values: Array = []
		values.resize(cols)
		values.fill(0.0)
		matrix.append(values)
	return matrix

static func _zero_vector(size: int) -> Array:
	var values: Array = []
	values.resize(size)
	values.fill(0.0)
	return values

static func _cell_ids(network: Dictionary, island: Array) -> Array:
	var result: Array = []
	for cell_index in island:
		result.append(String(network["cells"][cell_index]["id"]))
	return result

static func _find_bond_index(network: Dictionary, bond_id: String) -> int:
	for index in range(network["bonds"].size()):
		if String(network["bonds"][index].get("id", "")) == bond_id:
			return index
	return -1

static func _port_ref(element_id: String, port_name: String) -> String:
	return "%s::%s" % [element_id, port_name]

static func _normalize_dimension(source: Dictionary) -> Dictionary:
	var result := {}
	for key in DIMENSION_KEYS:
		result[key] = int(source.get(key, 0))
	return result

static func _sorted_dictionary(source: Dictionary) -> Dictionary:
	var result := {}
	var keys: Array = source.keys()
	keys.sort()
	for key in keys:
		result[key] = _canonical_value(source[key])
	return result

static func _canonical_value(value: Variant) -> Variant:
	if value is float:
		var number := float(value)
		if is_nan(number):
			return "NaN"
		if is_inf(number):
			return "-Inf" if number < 0.0 else "Inf"
		return number
	if value is Dictionary:
		return _sorted_dictionary(value)
	if value is Array:
		var items: Array = []
		for item in value:
			items.append(_canonical_value(item))
		return items
	return value
