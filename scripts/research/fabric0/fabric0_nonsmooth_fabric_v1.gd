class_name Fabric0NonsmoothFabricV1
extends RefCounted

const EPSILON := 1.0e-10
const PIVOT_EPSILON := 1.0e-12
const NEWTON_TOLERANCE := 1.0e-10
const NEWTON_MAX_ITERATIONS := 40
const NEWTON_MAX_LINE_SEARCH := 14
const GUARD_TOLERANCE := 1.0e-9
const MAX_BRANCH_COMBINATIONS := 256
const DIMENSION_KEYS := ["L", "M", "T", "I", "Theta", "N", "J"]

# =============================================================================
# DIMENSIONS
# =============================================================================

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

static func dim_time() -> Dictionary:
	return dim(0, 0, 1)

static func dim_current() -> Dictionary:
	return dim(0, 0, 0, 1)

static func dim_power() -> Dictionary:
	return dim(2, 1, -3)

static func dim_energy() -> Dictionary:
	return dim(2, 1, -2)

static func dim_voltage() -> Dictionary:
	return dim(2, 1, -3, -1)

static func dim_force() -> Dictionary:
	return dim(1, 1, -2)

static func dim_velocity() -> Dictionary:
	return dim(1, 0, -1)

static func dim_torque() -> Dictionary:
	return dim(2, 1, -2)

static func dim_angular_velocity() -> Dictionary:
	return dim(0, 0, -1)

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

static func _normalize_dimension(source: Dictionary) -> Dictionary:
	var result := {}
	for key in DIMENSION_KEYS:
		result[key] = int(source.get(key, 0))
	return result

# =============================================================================
# EXPRESSION LANGUAGE
# =============================================================================

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

# =============================================================================
# NONSMOOTH RELATION LANGUAGE
# =============================================================================

static func residual(expr: Dictionary, nominal: float) -> Dictionary:
	assert(nominal > 0.0)
	return {"expr": expr.duplicate(true), "nominal": nominal}

static func inequality(expr: Dictionary, nominal: float, label: String = "") -> Dictionary:
	assert(nominal > 0.0)
	return {"expr": expr.duplicate(true), "nominal": nominal, "label": label}

static func branch(
	branch_id: String,
	residuals: Array,
	inequalities: Array,
	priority: int = 0
) -> Dictionary:
	return {
		"id": branch_id,
		"residuals": residuals.duplicate(true),
		"inequalities": inequalities.duplicate(true),
		"priority": priority,
	}

# Exact complementarity compiler:
# a >= 0 ⟂ b >= 0  <=>  ({a=0,b>=0} union {b=0,a>=0}).
# shared_residuals allow multi-port laws such as equal-and-opposite reactions.
static func complementarity_branches(
	prefix: String,
	shared_residuals: Array,
	a_expr: Dictionary,
	a_nominal: float,
	b_expr: Dictionary,
	b_nominal: float,
	a_zero_priority: int = 0,
	b_zero_priority: int = 0
) -> Array:
	var a_residuals: Array = shared_residuals.duplicate(true)
	a_residuals.append(residual(a_expr, a_nominal))
	var b_residuals: Array = shared_residuals.duplicate(true)
	b_residuals.append(residual(b_expr, b_nominal))
	return [
		branch(
			"%s:a_zero" % prefix,
			a_residuals,
			[inequality(b_expr, b_nominal, "%s:b_nonnegative" % prefix)],
			a_zero_priority
		),
		branch(
			"%s:b_zero" % prefix,
			b_residuals,
			[inequality(a_expr, a_nominal, "%s:a_nonnegative" % prefix)],
			b_zero_priority
		),
	]

# =============================================================================
# NETWORK / ELEMENTS
# =============================================================================

static func new_network() -> Dictionary:
	return {
		"domains": {},
		"elements": {},
		"bonds": [],
		"cells": [],
		"diagnostics": [],
		"events": [],
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

static func equilibrium_terminal(
	element_id: String,
	domain: String,
	preferred_common: float,
	response_gain: float
) -> Dictionary:
	assert(response_gain >= 0.0)
	return _physical_element(
		element_id,
		{"op": "equilibrium_terminal", "preferred_common": preferred_common, "response_gain": response_gain},
		{"p": domain}
	)

static func fixed_balance_terminal(element_id: String, domain: String, balance_value: float) -> Dictionary:
	return _physical_element(
		element_id,
		{"op": "fixed_balance_terminal", "balance": balance_value},
		{"p": domain}
	)

static func ideal_common_constraint(element_id: String, domain: String, common_value: float) -> Dictionary:
	var result := _physical_element(
		element_id,
		{"op": "ideal_common_constraint", "common": common_value},
		{"p": domain}
	)
	result["state"]["constraint_lambdas"] = []
	return result

# Row: {terms:[{port, coefficient, coefficient_dimension}], nominal}
static func linear_power_map(element_id: String, port_domains: Dictionary, constraint_rows: Array) -> Dictionary:
	var result := _physical_element(
		element_id,
		{"op": "linear_power_map", "constraint_rows": constraint_rows.duplicate(true)},
		port_domains
	)
	result["state"]["constraint_lambdas"] = []
	return result

static func hybrid_relation(
	element_id: String,
	port_domains: Dictionary,
	parameters: Dictionary,
	branches: Array,
	initial_branch: String = ""
) -> Dictionary:
	var result := _physical_element(
		element_id,
		{
			"op": "hybrid_relation",
			"parameters": parameters.duplicate(true),
			"branches": branches.duplicate(true),
		},
		port_domains
	)
	result["state"]["active_branch"] = initial_branch
	result["state"]["last_guard_margins"] = []
	return result

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
		if not network["domains"].has(String(spec.get("domain", ""))):
			return false
	var copy: Dictionary = element.duplicate(true)
	var validation := _validate_element(network, copy)
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
	if String(spec_a.get("domain", "")) != String(spec_b.get("domain", "")):
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

static func set_equilibrium_preferred_common(network: Dictionary, element_id: String, value: float) -> bool:
	if not network["elements"].has(element_id):
		return false
	var element: Dictionary = network["elements"][element_id]
	if String(element["law"].get("op", "")) != "equilibrium_terminal":
		return false
	element["law"]["preferred_common"] = value
	return true

static func set_parameter_value(network: Dictionary, element_id: String, parameter_name: String, value: float) -> bool:
	if not network["elements"].has(element_id):
		return false
	var element: Dictionary = network["elements"][element_id]
	if String(element["law"].get("op", "")) != "hybrid_relation":
		return false
	if not element["law"]["parameters"].has(parameter_name):
		return false
	element["law"]["parameters"][parameter_name]["value"] = value
	return true

static func read_port_state(network: Dictionary, element_id: String, port_name: String) -> Dictionary:
	if not network["elements"].has(element_id):
		return {}
	return network["elements"][element_id]["state"]["ports"].get(port_name, {}).duplicate(true)

static func read_element_state(network: Dictionary, element_id: String, key: String) -> Variant:
	if not network["elements"].has(element_id):
		return null
	return network["elements"][element_id]["state"].get(key)

static func read_element_absorbed_power(network: Dictionary, element_id: String) -> float:
	if not network["elements"].has(element_id):
		return 0.0
	return float(network["elements"][element_id]["state"].get("absorbed_power", 0.0))

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

# =============================================================================
# VALIDATION
# =============================================================================

static func _validate_element(network: Dictionary, element: Dictionary) -> Dictionary:
	var op := String(element["law"].get("op", ""))
	match op:
		"equilibrium_terminal", "fixed_balance_terminal", "ideal_common_constraint":
			return {"ok": true}
		"linear_power_map":
			return _validate_power_map(network, element)
		"hybrid_relation":
			return _validate_hybrid_relation(network, element)
		_:
			return {"ok": false, "code": "UNKNOWN_ELEMENT_OP", "op": op}

static func _validate_power_map(network: Dictionary, element: Dictionary) -> Dictionary:
	var rows: Array = element["law"].get("constraint_rows", [])
	if rows.is_empty():
		return {"ok": false, "code": "POWER_MAP_EMPTY"}
	var normalized: Array = []
	for row_index in range(rows.size()):
		var row: Dictionary = rows[row_index]
		var nominal := float(row.get("nominal", 0.0))
		var terms: Array = row.get("terms", [])
		if nominal <= 0.0 or terms.size() < 2:
			return {"ok": false, "code": "POWER_MAP_BAD_ROW", "row": row_index}
		var row_dimension: Dictionary = {}
		var normalized_terms: Array = []
		for term in terms:
			var port_name := String(term.get("port", ""))
			if not element["ports"].has(port_name):
				return {"ok": false, "code": "POWER_MAP_BAD_PORT", "row": row_index, "port": port_name}
			if not term.has("coefficient_dimension"):
				return {"ok": false, "code": "POWER_MAP_MISSING_COEFFICIENT_DIMENSION", "row": row_index, "port": port_name}
			var coefficient_dimension := _normalize_dimension(term["coefficient_dimension"])
			var domain_id := String(element["ports"][port_name]["domain"])
			var common_dimension: Dictionary = network["domains"][domain_id]["common_dimension"]
			var term_dimension := dim_mul(coefficient_dimension, common_dimension)
			if row_dimension.is_empty():
				row_dimension = term_dimension
			elif not dim_equal(row_dimension, term_dimension):
				return {"ok": false, "code": "POWER_MAP_ROW_DIMENSION_MISMATCH", "row": row_index, "port": port_name}
			normalized_terms.append({
				"port": port_name,
				"coefficient": float(term.get("coefficient", 0.0)),
				"coefficient_dimension": coefficient_dimension,
			})
		normalized.append({"terms": normalized_terms, "nominal": nominal, "row_dimension": row_dimension})
	element["law"]["constraint_rows"] = normalized
	return {"ok": true}

static func _validate_hybrid_relation(network: Dictionary, element: Dictionary) -> Dictionary:
	var parameters: Dictionary = element["law"].get("parameters", {})
	for parameter_name in parameters.keys():
		var parameter: Dictionary = parameters[parameter_name]
		if not parameter.has("value") or not parameter.has("dimension"):
			return {"ok": false, "code": "HYBRID_BAD_PARAMETER", "parameter": String(parameter_name)}
		parameter["value"] = float(parameter["value"])
		parameter["dimension"] = _normalize_dimension(parameter["dimension"])
	var branches: Array = element["law"].get("branches", [])
	if branches.is_empty():
		return {"ok": false, "code": "HYBRID_NO_BRANCHES"}
	var seen := {}
	var normalized_branches: Array = []
	for branch_index in range(branches.size()):
		var branch_spec: Dictionary = branches[branch_index]
		var branch_id := String(branch_spec.get("id", ""))
		if branch_id.is_empty() or seen.has(branch_id):
			return {"ok": false, "code": "HYBRID_BAD_BRANCH_ID", "branch": branch_id}
		seen[branch_id] = true
		var residuals: Array = branch_spec.get("residuals", [])
		if residuals.size() != element["ports"].size():
			return {"ok": false, "code": "HYBRID_RESIDUAL_COUNT_MISMATCH", "branch": branch_id}
		var normalized_residuals: Array = []
		for item in residuals:
			var nominal := float(item.get("nominal", 0.0))
			if nominal <= 0.0 or not item.has("expr"):
				return {"ok": false, "code": "HYBRID_BAD_RESIDUAL", "branch": branch_id}
			var inferred := _infer_expr_dimension(network, element, item["expr"])
			if not bool(inferred.get("ok", false)):
				return {"ok": false, "code": "HYBRID_DIMENSION_ERROR", "branch": branch_id, "reason": inferred}
			normalized_residuals.append({
				"expr": item["expr"].duplicate(true),
				"nominal": nominal,
				"dimension": inferred["dimension"],
			})
		var normalized_inequalities: Array = []
		for item in branch_spec.get("inequalities", []):
			var nominal := float(item.get("nominal", 0.0))
			if nominal <= 0.0 or not item.has("expr"):
				return {"ok": false, "code": "HYBRID_BAD_INEQUALITY", "branch": branch_id}
			var inferred := _infer_expr_dimension(network, element, item["expr"])
			if not bool(inferred.get("ok", false)):
				return {"ok": false, "code": "HYBRID_DIMENSION_ERROR", "branch": branch_id, "reason": inferred}
			normalized_inequalities.append({
				"expr": item["expr"].duplicate(true),
				"nominal": nominal,
				"dimension": inferred["dimension"],
				"label": String(item.get("label", "")),
			})
		normalized_branches.append({
			"id": branch_id,
			"residuals": normalized_residuals,
			"inequalities": normalized_inequalities,
			"priority": int(branch_spec.get("priority", 0)),
		})
	element["law"]["parameters"] = parameters
	element["law"]["branches"] = normalized_branches
	var initial := String(element["state"].get("active_branch", ""))
	if not initial.is_empty() and not seen.has(initial):
		return {"ok": false, "code": "HYBRID_UNKNOWN_INITIAL_BRANCH", "branch": initial}
	return {"ok": true}

static func _infer_expr_dimension(network: Dictionary, element: Dictionary, expr: Dictionary) -> Dictionary:
	var op := String(expr.get("op", ""))
	match op:
		"constant":
			return {"ok": true, "dimension": _normalize_dimension(expr.get("dimension", {}))}
		"parameter":
			var name := String(expr.get("name", ""))
			if not element["law"]["parameters"].has(name):
				return {"ok": false, "reason": "UNKNOWN_PARAMETER", "name": name}
			return {"ok": true, "dimension": element["law"]["parameters"][name]["dimension"]}
		"common", "balance":
			var port_name := String(expr.get("port", ""))
			if not element["ports"].has(port_name):
				return {"ok": false, "reason": "UNKNOWN_PORT", "port": port_name}
			var domain_id := String(element["ports"][port_name]["domain"])
			var key := "common_dimension" if op == "common" else "balance_dimension"
			return {"ok": true, "dimension": network["domains"][domain_id][key]}
		"add", "sub":
			var a := _infer_expr_dimension(network, element, expr["a"])
			if not bool(a.get("ok", false)):
				return a
			var b := _infer_expr_dimension(network, element, expr["b"])
			if not bool(b.get("ok", false)):
				return b
			if not dim_equal(a["dimension"], b["dimension"]):
				return {"ok": false, "reason": "ADD_SUB_DIMENSION_MISMATCH", "left": dim_string(a["dimension"]), "right": dim_string(b["dimension"])}
			return {"ok": true, "dimension": a["dimension"]}
		"mul", "div":
			var a := _infer_expr_dimension(network, element, expr["a"])
			if not bool(a.get("ok", false)):
				return a
			var b := _infer_expr_dimension(network, element, expr["b"])
			if not bool(b.get("ok", false)):
				return b
			return {"ok": true, "dimension": dim_mul(a["dimension"], b["dimension"]) if op == "mul" else dim_div(a["dimension"], b["dimension"])}
		"neg":
			return _infer_expr_dimension(network, element, expr["a"])
		"pow_int":
			var a := _infer_expr_dimension(network, element, expr["a"])
			if not bool(a.get("ok", false)):
				return a
			return {"ok": true, "dimension": dim_pow(a["dimension"], int(expr.get("exponent", 1)))}
		"exp", "tanh":
			var a := _infer_expr_dimension(network, element, expr["a"])
			if not bool(a.get("ok", false)):
				return a
			if not dim_equal(a["dimension"], dim_dimensionless()):
				return {"ok": false, "reason": "TRANSCENDENTAL_REQUIRES_DIMENSIONLESS", "actual": dim_string(a["dimension"])}
			return {"ok": true, "dimension": dim_dimensionless()}
		_:
			return {"ok": false, "reason": "UNKNOWN_EXPRESSION_OP", "op": op}

# =============================================================================
# TOPOLOGY
# =============================================================================

static func _compile_cells(network: Dictionary) -> Dictionary:
	var refs: Array = []
	var domains := {}
	var element_ids: Array = network["elements"].keys()
	element_ids.sort()
	for element_id in element_ids:
		var port_names: Array = network["elements"][element_id]["ports"].keys()
		port_names.sort()
		for port_name in port_names:
			var ref := _port_ref(String(element_id), String(port_name))
			refs.append(ref)
			domains[ref] = String(network["elements"][element_id]["ports"][port_name]["domain"])
	var adjacency := {}
	for ref in refs:
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
	for root in refs:
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
		var domain := String(domains[component[0]])
		for ref in component:
			if String(domains[ref]) != domain:
				return {"ok": false, "code": "MIXED_DOMAIN_CELL", "ports": component}
		var index := cells.size()
		cells.append({
			"id": "cell/%s/%s" % [domain, String(component[0])],
			"domain": domain,
			"ports": component,
			"common": 0.0,
			"balance_residual": 0.0,
			"power_residual": 0.0,
			"status": "UNSOLVED",
		})
		for ref in component:
			cell_map[ref] = index
	return {"ok": true, "cells": cells, "cell_map": cell_map}

static func _compile_islands(network: Dictionary, cell_map: Dictionary) -> Array:
	var adjacency := {}
	for i in range(network["cells"].size()):
		adjacency[i] = []
	var element_ids: Array = network["elements"].keys()
	element_ids.sort()
	for element_id in element_ids:
		var indices: Array = []
		var port_names: Array = network["elements"][element_id]["ports"].keys()
		port_names.sort()
		for port_name in port_names:
			var cell_index := int(cell_map[_port_ref(String(element_id), String(port_name))])
			if cell_index not in indices:
				indices.append(cell_index)
		for left in range(indices.size()):
			for right in range(left + 1, indices.size()):
				var a := int(indices[left])
				var b := int(indices[right])
				if b not in adjacency[a]: adjacency[a].append(b)
				if a not in adjacency[b]: adjacency[b].append(a)
	var visited := {}
	var islands: Array = []
	for root in range(network["cells"].size()):
		if visited.has(root): continue
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
	return islands

# =============================================================================
# ACTIVE-SET / BRANCH SOLVE
# =============================================================================

static func solve(network: Dictionary) -> Dictionary:
	network["diagnostics"] = []
	var compiled := _compile_cells(network)
	if not bool(compiled.get("ok", false)):
		network["diagnostics"].append(compiled)
		return {"ok": false, "diagnostics": network["diagnostics"].duplicate(true)}
	network["cells"] = compiled["cells"]
	var cell_map: Dictionary = compiled["cell_map"]
	var islands := _compile_islands(network, cell_map)
	var total_combinations := 0
	var total_valid := 0
	var total_iterations := 0
	var ambiguity_count := 0
	for island in islands:
		var result := _solve_island_active_set(network, cell_map, island)
		total_combinations += int(result.get("combinations_tried", 0))
		total_valid += int(result.get("valid_candidates", 0))
		total_iterations += int(result.get("iterations", 0))
		ambiguity_count += maxi(int(result.get("valid_candidates", 0)) - 1, 0)
		if not bool(result.get("ok", false)):
			network["solve_revision"] = int(network.get("solve_revision", 0)) + 1
			return {"ok": false, "diagnostics": network["diagnostics"].duplicate(true)}
	network["solver_stats"] = {
		"islands": islands.size(),
		"branch_combinations_tried": total_combinations,
		"valid_candidates": total_valid,
		"ambiguity_count": ambiguity_count,
		"newton_iterations": total_iterations,
	}
	network["solve_revision"] = int(network.get("solve_revision", 0)) + 1
	return {
		"ok": true,
		"cell_count": network["cells"].size(),
		"island_count": islands.size(),
		"solver_stats": network["solver_stats"].duplicate(true),
	}

static func _solve_island_active_set(network: Dictionary, cell_map: Dictionary, island: Array) -> Dictionary:
	var hybrid_ids: Array = []
	var element_ids: Array = network["elements"].keys()
	element_ids.sort()
	for element_id in element_ids:
		var element: Dictionary = network["elements"][element_id]
		if String(element["law"].get("op", "")) != "hybrid_relation":
			continue
		var touches := false
		for port_name in element["ports"].keys():
			if int(cell_map[_port_ref(String(element_id), String(port_name))]) in island:
				touches = true
				break
		if touches:
			hybrid_ids.append(String(element_id))
	var assignments := _enumerate_assignments(network, hybrid_ids)
	if assignments.size() > MAX_BRANCH_COMBINATIONS:
		var overflow := {"code": "ACTIVE_SET_COMBINATION_LIMIT", "count": assignments.size(), "limit": MAX_BRANCH_COMBINATIONS}
		network["diagnostics"].append(overflow)
		return {"ok": false, "combinations_tried": 0, "valid_candidates": 0}
	var candidates: Array = []
	var tried := 0
	var iterations := 0
	for assignment in assignments:
		tried += 1
		var model := _build_model(network, cell_map, island, assignment)
		if not bool(model.get("ok", false)):
			continue
		var solved := _solve_model(network, model)
		iterations += int(solved.get("iterations", 0))
		if not bool(solved.get("ok", false)):
			continue
		var guard_check := _evaluate_assignment_guards(network, model, solved["x"], assignment)
		if not bool(guard_check.get("ok", false)):
			continue
		candidates.append({
			"assignment": assignment.duplicate(true),
			"model": model,
			"x": solved["x"],
			"iterations": int(solved.get("iterations", 0)),
			"guard_margins": guard_check["guard_margins"],
			"score": _assignment_score(network, assignment),
		})
	if candidates.is_empty():
		var failure := {
			"code": "NO_ADMISSIBLE_NONSMOOTH_BRANCH",
			"cells": _cell_ids(network, island),
			"combinations_tried": tried,
		}
		network["diagnostics"].append(failure)
		for cell_index in island:
			network["cells"][cell_index]["status"] = "NO_ADMISSIBLE_NONSMOOTH_BRANCH"
		return {"ok": false, "combinations_tried": tried, "valid_candidates": 0, "iterations": iterations}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa: Array = a["score"]
		var sb: Array = b["score"]
		if int(sa[0]) != int(sb[0]): return int(sa[0]) < int(sb[0])
		if int(sa[1]) != int(sb[1]): return int(sa[1]) < int(sb[1])
		return String(sa[2]) < String(sb[2])
	)
	var selected: Dictionary = candidates[0]
	_apply_solution(network, selected["model"], selected["x"], selected["assignment"], selected["guard_margins"])
	return {
		"ok": true,
		"combinations_tried": tried,
		"valid_candidates": candidates.size(),
		"iterations": iterations,
	}

static func _enumerate_assignments(network: Dictionary, hybrid_ids: Array) -> Array:
	var assignments: Array = [{}]
	for element_id in hybrid_ids:
		var element: Dictionary = network["elements"][element_id]
		var branches: Array = element["law"]["branches"].duplicate(true)
		var active := String(element["state"].get("active_branch", ""))
		branches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var a_active := String(a["id"]) == active
			var b_active := String(b["id"]) == active
			if a_active != b_active: return a_active
			if int(a["priority"]) != int(b["priority"]): return int(a["priority"]) < int(b["priority"])
			return String(a["id"]) < String(b["id"])
		)
		var next: Array = []
		for assignment in assignments:
			for branch_spec in branches:
				var copy: Dictionary = assignment.duplicate(true)
				copy[element_id] = String(branch_spec["id"])
				next.append(copy)
		assignments = next
		if assignments.size() > MAX_BRANCH_COMBINATIONS:
			break
	return assignments

static func _assignment_score(network: Dictionary, assignment: Dictionary) -> Array:
	var changes := 0
	var priority := 0
	var keys: Array = assignment.keys()
	keys.sort()
	var signature_parts: Array[String] = []
	for element_id in keys:
		var selected := String(assignment[element_id])
		var active := String(network["elements"][element_id]["state"].get("active_branch", ""))
		if not active.is_empty() and selected != active:
			changes += 1
		var branch_spec := _branch_by_id(network["elements"][element_id], selected)
		priority += int(branch_spec.get("priority", 0))
		signature_parts.append("%s=%s" % [String(element_id), selected])
	return [changes, priority, "|".join(signature_parts)]

static func _build_model(network: Dictionary, cell_map: Dictionary, island: Array, assignment: Dictionary) -> Dictionary:
	var local_cell_unknown := {}
	var initial_x: Array = []
	var unknown_nominals: Array = []
	for global_cell in island:
		local_cell_unknown[int(global_cell)] = initial_x.size()
		initial_x.append(_initial_cell_guess(network, int(global_cell)))
		var domain_id := String(network["cells"][global_cell]["domain"])
		unknown_nominals.append(float(network["domains"][domain_id]["common_nominal"]))

	var hybrid_balance_indices := {}
	var hybrid_ids: Array = assignment.keys()
	hybrid_ids.sort()
	for element_id in hybrid_ids:
		var element: Dictionary = network["elements"][element_id]
		var port_names: Array = element["ports"].keys()
		port_names.sort()
		for port_name in port_names:
			var key := _port_ref(String(element_id), String(port_name))
			hybrid_balance_indices[key] = initial_x.size()
			initial_x.append(float(element["state"]["ports"][port_name].get("balance", 0.0)))
			var domain_id := String(element["ports"][port_name]["domain"])
			unknown_nominals.append(float(network["domains"][domain_id]["balance_nominal"]))

	var constraints: Array = []
	var element_ids: Array = network["elements"].keys()
	element_ids.sort()
	for element_id in element_ids:
		var element: Dictionary = network["elements"][element_id]
		var op := String(element["law"].get("op", ""))
		if op == "ideal_common_constraint":
			var global_cell := int(cell_map[_port_ref(String(element_id), "p")])
			if global_cell not in island: continue
			var domain_id := String(element["ports"]["p"]["domain"])
			constraints.append({
				"element_id": String(element_id),
				"row_index": 0,
				"value": float(element["law"]["common"]),
				"nominal": float(network["domains"][domain_id]["common_nominal"]),
				"terms": [{"cell": int(local_cell_unknown[global_cell]), "port": "p", "coefficient": 1.0}],
			})
		elif op == "linear_power_map":
			var touches := false
			for port_name in element["ports"].keys():
				if int(cell_map[_port_ref(String(element_id), String(port_name))]) in island:
					touches = true
			if not touches: continue
			for row_index in range(element["law"]["constraint_rows"].size()):
				var row: Dictionary = element["law"]["constraint_rows"][row_index]
				var terms: Array = []
				for term in row["terms"]:
					var port_name := String(term["port"])
					var global_cell := int(cell_map[_port_ref(String(element_id), port_name)])
					terms.append({"cell": int(local_cell_unknown[global_cell]), "port": port_name, "coefficient": float(term["coefficient"])})
				constraints.append({
					"element_id": String(element_id),
					"row_index": row_index,
					"value": 0.0,
					"nominal": float(row["nominal"]),
					"terms": terms,
				})

	for constraint in constraints:
		constraint["lambda_index"] = initial_x.size()
		initial_x.append(0.0)
		unknown_nominals.append(1.0)

	var row_nominals: Array = []
	for global_cell in island:
		var domain_id := String(network["cells"][global_cell]["domain"])
		row_nominals.append(float(network["domains"][domain_id]["balance_nominal"]))
	for constraint in constraints:
		row_nominals.append(float(constraint["nominal"]))
	for element_id in hybrid_ids:
		var branch_spec := _branch_by_id(network["elements"][element_id], String(assignment[element_id]))
		for residual_spec in branch_spec["residuals"]:
			row_nominals.append(float(residual_spec["nominal"]))
	if row_nominals.size() != initial_x.size():
		return {"ok": false, "code": "NON_SQUARE_ACTIVE_SET_MODEL", "rows": row_nominals.size(), "unknowns": initial_x.size()}
	return {
		"ok": true,
		"island": island,
		"cell_map": cell_map,
		"local_cell_unknown": local_cell_unknown,
		"hybrid_balance_indices": hybrid_balance_indices,
		"hybrid_ids": hybrid_ids,
		"assignment": assignment,
		"constraints": constraints,
		"initial_x": initial_x,
		"unknown_nominals": unknown_nominals,
		"row_nominals": row_nominals,
	}

static func _solve_model(network: Dictionary, model: Dictionary) -> Dictionary:
	var x: Array = model["initial_x"].duplicate(true)
	var last_norm := INF
	for iteration in range(NEWTON_MAX_ITERATIONS):
		var assembled := _assemble(network, model, x)
		if not bool(assembled.get("ok", false)):
			return {"ok": false, "iterations": iteration + 1, "code": assembled.get("code", "ASSEMBLY_FAILED")}
		var norm := _normalized_norm(assembled["residual"], model["row_nominals"])
		last_norm = norm
		if norm <= NEWTON_TOLERANCE:
			var rank_probe := _solve_dense(assembled["jacobian"], _zero_vector(x.size()))
			if not bool(rank_probe.get("ok", false)):
				return {"ok": false, "iterations": iteration + 1, "code": "SINGULAR_ACTIVE_SET_MANIFOLD", "normalized_residual": norm}
			return {"ok": true, "iterations": iteration + 1, "x": x, "normalized_residual": norm}
		var rhs: Array = []
		for value in assembled["residual"]:
			rhs.append(-float(value))
		var step := _solve_dense(assembled["jacobian"], rhs)
		if not bool(step.get("ok", false)):
			return {"ok": false, "iterations": iteration + 1, "code": "ACTIVE_SET_SINGULAR_JACOBIAN", "normalized_residual": norm}
		var dx: Array = step["x"]
		var alpha := 1.0
		var accepted := false
		for _line in range(NEWTON_MAX_LINE_SEARCH):
			var candidate: Array = x.duplicate(true)
			for i in range(candidate.size()):
				candidate[i] = float(candidate[i]) + alpha * float(dx[i])
			var candidate_assembled := _assemble(network, model, candidate)
			if bool(candidate_assembled.get("ok", false)):
				var candidate_norm := _normalized_norm(candidate_assembled["residual"], model["row_nominals"])
				if candidate_norm < norm or candidate_norm <= NEWTON_TOLERANCE:
					x = candidate
					accepted = true
					break
			alpha *= 0.5
		if not accepted:
			return {"ok": false, "iterations": iteration + 1, "code": "ACTIVE_SET_LINE_SEARCH_FAILED", "normalized_residual": norm}
	return {"ok": false, "iterations": NEWTON_MAX_ITERATIONS, "code": "ACTIVE_SET_NO_CONVERGENCE", "normalized_residual": last_norm}

static func _assemble(network: Dictionary, model: Dictionary, x: Array) -> Dictionary:
	var size := x.size()
	var residual_values := _zero_vector(size)
	var jacobian := _zero_matrix(size, size)
	var island: Array = model["island"]
	var cell_map: Dictionary = model["cell_map"]
	var local_cell_unknown: Dictionary = model["local_cell_unknown"]
	var hybrid_balance_indices: Dictionary = model["hybrid_balance_indices"]

	var element_ids: Array = network["elements"].keys()
	element_ids.sort()
	for element_id in element_ids:
		var element: Dictionary = network["elements"][element_id]
		var op := String(element["law"].get("op", ""))
		var touches := false
		for port_name in element["ports"].keys():
			if int(cell_map[_port_ref(String(element_id), String(port_name))]) in island:
				touches = true
				break
		if not touches: continue
		match op:
			"equilibrium_terminal":
				var global_cell := int(cell_map[_port_ref(String(element_id), "p")])
				var q := int(local_cell_unknown[global_cell])
				var g := float(element["law"]["response_gain"])
				residual_values[q] += g * (float(element["law"]["preferred_common"]) - float(x[q]))
				jacobian[q][q] -= g
			"fixed_balance_terminal":
				var global_cell := int(cell_map[_port_ref(String(element_id), "p")])
				residual_values[int(local_cell_unknown[global_cell])] += float(element["law"]["balance"])
			"hybrid_relation":
				var port_names: Array = element["ports"].keys()
				port_names.sort()
				for port_name in port_names:
					var global_cell := int(cell_map[_port_ref(String(element_id), String(port_name))])
					var q := int(local_cell_unknown[global_cell])
					var b := int(hybrid_balance_indices[_port_ref(String(element_id), String(port_name))])
					residual_values[q] += float(x[b])
					jacobian[q][b] += 1.0

	var row := island.size()
	for constraint in model["constraints"]:
		var lambda_index := int(constraint["lambda_index"])
		var lambda := float(x[lambda_index])
		residual_values[row] -= float(constraint["value"])
		for term in constraint["terms"]:
			var q := int(term["cell"])
			var c := float(term["coefficient"])
			residual_values[q] -= c * lambda
			jacobian[q][lambda_index] -= c
			residual_values[row] += c * float(x[q])
			jacobian[row][q] += c
		row += 1

	for element_id in model["hybrid_ids"]:
		var element: Dictionary = network["elements"][element_id]
		var branch_spec := _branch_by_id(element, String(model["assignment"][element_id]))
		for residual_spec in branch_spec["residuals"]:
			var evaluated := _eval_expr_dual(network, element, residual_spec["expr"], model, x)
			if not bool(evaluated.get("ok", false)):
				return evaluated
			residual_values[row] = float(evaluated["value"])
			for unknown_index in evaluated["grad"].keys():
				jacobian[row][int(unknown_index)] += float(evaluated["grad"][unknown_index])
			row += 1
	return {"ok": true, "residual": residual_values, "jacobian": jacobian}

static func _evaluate_assignment_guards(network: Dictionary, model: Dictionary, x: Array, assignment: Dictionary) -> Dictionary:
	var margins := {}
	for element_id in model["hybrid_ids"]:
		var element: Dictionary = network["elements"][element_id]
		var branch_spec := _branch_by_id(element, String(assignment[element_id]))
		var local_margins: Array = []
		for guard in branch_spec["inequalities"]:
			var evaluated := _eval_expr_dual(network, element, guard["expr"], model, x)
			if not bool(evaluated.get("ok", false)):
				return {"ok": false}
			var margin := float(evaluated["value"]) / float(guard["nominal"])
			local_margins.append({"label": String(guard.get("label", "")), "margin": margin})
			if margin < -GUARD_TOLERANCE:
				return {"ok": false}
		margins[element_id] = local_margins
	return {"ok": true, "guard_margins": margins}

static func _apply_solution(network: Dictionary, model: Dictionary, x: Array, assignment: Dictionary, guard_margins: Dictionary) -> void:
	var island: Array = model["island"]
	var cell_map: Dictionary = model["cell_map"]
	var local_cell_unknown: Dictionary = model["local_cell_unknown"]
	var hybrid_balance_indices: Dictionary = model["hybrid_balance_indices"]
	for global_cell in island:
		var common := float(x[int(local_cell_unknown[int(global_cell)])])
		network["cells"][global_cell]["common"] = common
		network["cells"][global_cell]["status"] = "SOLVED"

	var reactions := {}
	for constraint in model["constraints"]:
		var element_id := String(constraint["element_id"])
		if not reactions.has(element_id): reactions[element_id] = {}
		var lambda := float(x[int(constraint["lambda_index"])])
		for term in constraint["terms"]:
			var port_name := String(term["port"])
			reactions[element_id][port_name] = float(reactions[element_id].get(port_name, 0.0)) - float(term["coefficient"]) * lambda

	var element_ids: Array = network["elements"].keys()
	element_ids.sort()
	for element_id in element_ids:
		var element: Dictionary = network["elements"][element_id]
		var touches := false
		for port_name in element["ports"].keys():
			if int(cell_map[_port_ref(String(element_id), String(port_name))]) in island:
				touches = true
				break
		if not touches: continue
		var op := String(element["law"].get("op", ""))
		match op:
			"equilibrium_terminal":
				var global_cell := int(cell_map[_port_ref(String(element_id), "p")])
				var common := float(x[int(local_cell_unknown[global_cell])])
				var balance_value := float(element["law"]["response_gain"]) * (float(element["law"]["preferred_common"]) - common)
				_set_port_state(element, "p", common, balance_value)
			"fixed_balance_terminal":
				var global_cell := int(cell_map[_port_ref(String(element_id), "p")])
				_set_port_state(element, "p", float(x[int(local_cell_unknown[global_cell])]), float(element["law"]["balance"]))
			"ideal_common_constraint", "linear_power_map":
				for port_name in element["ports"].keys():
					var global_cell := int(cell_map[_port_ref(String(element_id), String(port_name))])
					_set_port_state(element, String(port_name), float(x[int(local_cell_unknown[global_cell])]), float(reactions.get(String(element_id), {}).get(String(port_name), 0.0)))
			"hybrid_relation":
				var old_branch := String(element["state"].get("active_branch", ""))
				var new_branch := String(assignment[element_id])
				for port_name in element["ports"].keys():
					var global_cell := int(cell_map[_port_ref(String(element_id), String(port_name))])
					var balance_index := int(hybrid_balance_indices[_port_ref(String(element_id), String(port_name))])
					_set_port_state(element, String(port_name), float(x[int(local_cell_unknown[global_cell])]), float(x[balance_index]))
				element["state"]["active_branch"] = new_branch
				element["state"]["last_guard_margins"] = guard_margins.get(String(element_id), []).duplicate(true)
				if not old_branch.is_empty() and old_branch != new_branch and int(network.get("solve_revision", 0)) > 0:
					network["events"].append({
						"type": "nonsmooth_transition",
						"element_id": String(element_id),
						"from": old_branch,
						"to": new_branch,
						"revision": int(network.get("solve_revision", 0)) + 1,
					})
		var power_into_cells := 0.0
		for port_name in element["state"]["ports"].keys():
			power_into_cells += float(element["state"]["ports"][port_name]["power_into_cell"])
		element["state"]["absorbed_power"] = -power_into_cells
	_compute_cell_residuals(network, island)

# =============================================================================
# EXPRESSION EVALUATION / AD
# =============================================================================

static func _eval_expr_dual(network: Dictionary, element: Dictionary, expr: Dictionary, model: Dictionary, x: Array) -> Dictionary:
	var op := String(expr.get("op", ""))
	match op:
		"constant": return {"ok": true, "value": float(expr.get("value", 0.0)), "grad": {}}
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
			var index := int(model["hybrid_balance_indices"][_port_ref(String(element["id"]), port_name)])
			return {"ok": true, "value": float(x[index]), "grad": {index: 1.0}}
		"neg":
			var a := _eval_expr_dual(network, element, expr["a"], model, x)
			if not bool(a.get("ok", false)): return a
			return {"ok": true, "value": -float(a["value"]), "grad": _grad_scaled(a["grad"], -1.0)}
		"add", "sub", "mul", "div":
			var a := _eval_expr_dual(network, element, expr["a"], model, x)
			if not bool(a.get("ok", false)): return a
			var b := _eval_expr_dual(network, element, expr["b"], model, x)
			if not bool(b.get("ok", false)): return b
			var av := float(a["value"])
			var bv := float(b["value"])
			match op:
				"add": return {"ok": true, "value": av + bv, "grad": _grad_combine(a["grad"], 1.0, b["grad"], 1.0)}
				"sub": return {"ok": true, "value": av - bv, "grad": _grad_combine(a["grad"], 1.0, b["grad"], -1.0)}
				"mul": return {"ok": true, "value": av * bv, "grad": _grad_combine(a["grad"], bv, b["grad"], av)}
				"div":
					if absf(bv) <= 1.0e-15: return {"ok": false, "code": "DIVISION_BY_ZERO"}
					return {"ok": true, "value": av / bv, "grad": _grad_combine(a["grad"], 1.0 / bv, b["grad"], -av / (bv * bv))}
		"pow_int":
			var a := _eval_expr_dual(network, element, expr["a"], model, x)
			if not bool(a.get("ok", false)): return a
			var n := int(expr.get("exponent", 1))
			var av := float(a["value"])
			if n < 0 and absf(av) <= 1.0e-15: return {"ok": false, "code": "NEGATIVE_POWER_ZERO"}
			var value := pow(av, n)
			var derivative := 0.0 if n == 0 else float(n) * pow(av, n - 1)
			return {"ok": true, "value": value, "grad": _grad_scaled(a["grad"], derivative)}
		"exp":
			var a := _eval_expr_dual(network, element, expr["a"], model, x)
			if not bool(a.get("ok", false)): return a
			var av := float(a["value"])
			if av > 700.0: return {"ok": false, "code": "EXP_OVERFLOW"}
			var value := exp(av)
			return {"ok": true, "value": value, "grad": _grad_scaled(a["grad"], value)}
		"tanh":
			var a := _eval_expr_dual(network, element, expr["a"], model, x)
			if not bool(a.get("ok", false)): return a
			var value := tanh(float(a["value"]))
			return {"ok": true, "value": value, "grad": _grad_scaled(a["grad"], 1.0 - value * value)}
		_:
			return {"ok": false, "code": "UNKNOWN_EXPRESSION_OP", "op": op}
	return {"ok": false, "code": "UNKNOWN_EXPRESSION_OP", "op": op}

# =============================================================================
# MISC / HASH
# =============================================================================

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
	for domain_id in domain_ids: domains[domain_id] = _canonical_value(network["domains"][domain_id])
	var element_ids: Array = network["elements"].keys()
	element_ids.sort()
	var elements: Array = []
	for element_id in element_ids:
		var element: Dictionary = network["elements"][element_id]
		elements.append({"id": String(element_id), "law": _canonical_value(element["law"]), "ports": _canonical_value(element["ports"]), "state": _canonical_value(element["state"])})
	var bonds: Array = []
	for bond in network["bonds"]: bonds.append(_canonical_value(bond))
	bonds.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["id"]) < String(b["id"]))
	return {
		"domains": domains,
		"elements": elements,
		"bonds": bonds,
		"cells": _canonical_value(network["cells"]),
		"events": _canonical_value(network["events"]),
		"solve_revision": int(network["solve_revision"]),
		"solver_stats": _canonical_value(network["solver_stats"]),
	}

static func _canonical_value(value: Variant) -> Variant:
	if value is float:
		var number := float(value)
		if is_nan(number): return "NaN"
		if is_inf(number): return "-Inf" if number < 0.0 else "Inf"
		return number
	if value is Dictionary:
		var result := {}
		var keys: Array = value.keys()
		keys.sort()
		for key in keys: result[key] = _canonical_value(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value: result.append(_canonical_value(item))
		return result
	return value

static func _initial_cell_guess(network: Dictionary, global_cell: int) -> float:
	var cell: Dictionary = network["cells"][global_cell]
	var values: Array[float] = []
	for ref in cell["ports"]:
		var parts := String(ref).split("::", false, 1)
		var previous := float(network["elements"][String(parts[0])]["state"]["ports"][String(parts[1])].get("common", 0.0))
		if absf(previous) > EPSILON: values.append(previous)
	if not values.is_empty():
		var sum := 0.0
		for value in values: sum += value
		return sum / float(values.size())
	var weighted := 0.0
	var weight := 0.0
	for ref in cell["ports"]:
		var parts := String(ref).split("::", false, 1)
		var element: Dictionary = network["elements"][String(parts[0])]
		if String(element["law"].get("op", "")) == "equilibrium_terminal":
			var g := float(element["law"]["response_gain"])
			weighted += g * float(element["law"]["preferred_common"])
			weight += g
	if weight > EPSILON: return weighted / weight
	return 0.0

static func _branch_by_id(element: Dictionary, branch_id: String) -> Dictionary:
	for branch_spec in element["law"]["branches"]:
		if String(branch_spec["id"]) == branch_id: return branch_spec
	return {}

static func _set_port_state(element: Dictionary, port_name: String, common: float, balance_value: float) -> void:
	element["state"]["ports"][port_name] = {
		"common": common,
		"balance": balance_value,
		"power_into_cell": common * balance_value,
	}

static func _compute_cell_residuals(network: Dictionary, island: Array) -> void:
	for global_cell in island:
		var cell: Dictionary = network["cells"][global_cell]
		var balance_sum := 0.0
		for ref in cell["ports"]:
			var parts := String(ref).split("::", false, 1)
			balance_sum += float(network["elements"][String(parts[0])]["state"]["ports"][String(parts[1])]["balance"])
		cell["balance_residual"] = balance_sum
		cell["power_residual"] = float(cell["common"]) * balance_sum

static func _normalized_norm(values: Array, nominals: Array) -> float:
	var result := 0.0
	for i in range(values.size()):
		result = maxf(result, absf(float(values[i])) / maxf(float(nominals[i]), EPSILON))
	return result

static func _grad_scaled(source: Dictionary, scale: float) -> Dictionary:
	var result := {}
	for key in source.keys(): result[key] = float(source[key]) * scale
	return result

static func _grad_combine(a: Dictionary, scale_a: float, b: Dictionary, scale_b: float) -> Dictionary:
	var result := {}
	for key in a.keys(): result[key] = float(result.get(key, 0.0)) + float(a[key]) * scale_a
	for key in b.keys(): result[key] = float(result.get(key, 0.0)) + float(b[key]) * scale_b
	return result

static func _physical_element(element_id: String, law: Dictionary, port_domains: Dictionary) -> Dictionary:
	var ports := {}
	var port_states := {}
	for port_name in port_domains.keys():
		ports[port_name] = {"direction": "physical", "domain": String(port_domains[port_name])}
		port_states[port_name] = {"common": 0.0, "balance": 0.0, "power_into_cell": 0.0}
	return {"id": element_id, "law": law.duplicate(true), "ports": ports, "state": {"ports": port_states, "absorbed_power": 0.0}}

static func _port_ref(element_id: String, port_name: String) -> String:
	return "%s::%s" % [element_id, port_name]

static func _find_bond_index(network: Dictionary, bond_id: String) -> int:
	for i in range(network["bonds"].size()):
		if String(network["bonds"][i].get("id", "")) == bond_id: return i
	return -1

static func _cell_ids(network: Dictionary, island: Array) -> Array:
	var result: Array = []
	for index in island: result.append(String(network["cells"][index]["id"]))
	return result

static func _zero_matrix(rows: int, cols: int) -> Array:
	var result: Array = []
	for _row in range(rows):
		var values: Array = []
		values.resize(cols)
		values.fill(0.0)
		result.append(values)
	return result

static func _zero_vector(size: int) -> Array:
	var result: Array = []
	result.resize(size)
	result.fill(0.0)
	return result

static func _solve_dense(matrix: Array, rhs: Array) -> Dictionary:
	var size := rhs.size()
	if matrix.size() != size: return {"ok": false}
	if size == 0: return {"ok": true, "x": []}
	var a: Array = []
	for row in range(size):
		if matrix[row].size() != size: return {"ok": false}
		var values: Array = []
		for col in range(size): values.append(float(matrix[row][col]))
		a.append(values)
	var b: Array = []
	for value in rhs: b.append(float(value))
	for col in range(size):
		var pivot := col
		var pivot_abs := absf(float(a[col][col]))
		for row in range(col + 1, size):
			var candidate := absf(float(a[row][col]))
			if candidate > pivot_abs:
				pivot = row
				pivot_abs = candidate
		if pivot_abs <= PIVOT_EPSILON: return {"ok": false}
		if pivot != col:
			var tmp_row = a[col]
			a[col] = a[pivot]
			a[pivot] = tmp_row
			var tmp_b = b[col]
			b[col] = b[pivot]
			b[pivot] = tmp_b
		var pv := float(a[col][col])
		for j in range(col, size): a[col][j] = float(a[col][j]) / pv
		b[col] = float(b[col]) / pv
		for row in range(size):
			if row == col: continue
			var factor := float(a[row][col])
			if absf(factor) <= EPSILON: continue
			for j in range(col, size): a[row][j] = float(a[row][j]) - factor * float(a[col][j])
			b[row] = float(b[row]) - factor * float(b[col])
	return {"ok": true, "x": b}
