class_name Fabric0ConservationFabricV2
extends RefCounted

const EPSILON := 1.0e-10
const PIVOT_EPSILON := 1.0e-12

static func new_network() -> Dictionary:
	return {
		"domains": {},
		"elements": {},
		"bonds": [],
		"cells": [],
		"diagnostics": [],
		"solve_revision": 0,
	}

static func register_domain(
	network: Dictionary,
	domain_id: String,
	common_quantity: String,
	balance_quantity: String,
	common_unit: String = "",
	balance_unit: String = ""
) -> bool:
	if domain_id.is_empty() or network["domains"].has(domain_id):
		return false
	if common_quantity.is_empty() or balance_quantity.is_empty():
		return false
	network["domains"][domain_id] = {
		"common_quantity": common_quantity,
		"balance_quantity": balance_quantity,
		"common_unit": common_unit,
		"balance_unit": balance_unit,
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
		{
			"op": "equilibrium_terminal",
			"preferred_common": preferred_common,
			"response_gain": response_gain,
		},
		{"p": domain},
	)

static func fixed_balance_terminal(
	element_id: String,
	domain: String,
	balance: float
) -> Dictionary:
	return _physical_element(
		element_id,
		{"op": "fixed_balance_terminal", "balance": balance},
		{"p": domain},
	)

static func ideal_common_constraint(
	element_id: String,
	domain: String,
	common: float
) -> Dictionary:
	return _physical_element(
		element_id,
		{"op": "ideal_common_constraint", "common": common},
		{"p": domain},
	)

static func linear_difference_coupler(
	element_id: String,
	domain: String,
	response_gain: float
) -> Dictionary:
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
	result["state"]["energy"] = 0.5 * capacity * initial_common * initial_common
	result["state"]["last_delta_energy"] = 0.0
	result["state"]["last_absorbed_work"] = 0.0
	result["state"]["last_numerical_dissipation"] = 0.0
	return result

static func linear_power_map(
	element_id: String,
	port_domains: Dictionary,
	constraint_rows: Array
) -> Dictionary:
	assert(port_domains.size() >= 2)
	assert(not constraint_rows.is_empty())
	var normalized_rows: Array = []
	var used_ports := {}
	for row in constraint_rows:
		assert(row is Dictionary)
		var coefficients := {}
		var nonzero := 0
		for port_name in row.keys():
			assert(port_domains.has(port_name))
			var coefficient := float(row[port_name])
			if absf(coefficient) > EPSILON:
				nonzero += 1
				used_ports[String(port_name)] = true
			coefficients[String(port_name)] = coefficient
		assert(nonzero >= 2)
		normalized_rows.append(coefficients)
	assert(used_ports.size() == port_domains.size())
	var result := _physical_element(
		element_id,
		{"op": "linear_power_map", "constraint_rows": normalized_rows},
		port_domains,
	)
	result["state"]["constraint_lambdas"] = []
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
		var domain := String(spec.get("domain", ""))
		if not network["domains"].has(domain):
			return false
	network["elements"][element_id] = element.duplicate(true)
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
	}

static func _solve_network(network: Dictionary, delta: float, commit_dynamic: bool) -> Dictionary:
	network["diagnostics"] = []
	network["cells"] = []
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
	for island in islands:
		var result := _solve_island(network, cell_map, island, delta)
		if not bool(result.get("ok", false)):
			all_ok = false
	if all_ok and commit_dynamic:
		_commit_dynamic_state(network, delta)
	network["solve_revision"] = int(network.get("solve_revision", 0)) + 1
	return {
		"ok": all_ok,
		"cell_count": network["cells"].size(),
		"island_count": islands.size(),
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
			var ref := _port_ref(element_id, String(port_name))
			var cell_index := int(cell_map[ref])
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

static func _solve_island(network: Dictionary, cell_map: Dictionary, island: Array, delta: float) -> Dictionary:
	var local_index := {}
	for index in range(island.size()):
		local_index[int(island[index])] = index

	var size := island.size()
	var matrix := _zero_matrix(size, size)
	var rhs := _zero_vector(size)
	var constraints: Array = []

	var element_ids: Array = network["elements"].keys()
	element_ids.sort()
	for element_id in element_ids:
		var element: Dictionary = network["elements"][element_id]
		var port_names: Array = element["ports"].keys()
		port_names.sort()
		var global_cells: Array = []
		for port_name in port_names:
			var ref := _port_ref(element_id, String(port_name))
			var global_cell := int(cell_map[ref])
			if global_cell in island:
				global_cells.append(global_cell)
		if global_cells.is_empty():
			continue
		if global_cells.size() != port_names.size():
			var split := {"ok": false, "code": "ELEMENT_SPLIT_ACROSS_SOLVE_ISLAND", "element_id": element_id}
			_mark_island_failed(network, island, String(split["code"]))
			network["diagnostics"].append(split)
			return split

		var op := String(element["law"].get("op", ""))
		match op:
			"equilibrium_terminal":
				var g := float(element["law"].get("response_gain", 0.0))
				var preferred := float(element["law"].get("preferred_common", 0.0))
				var cell := int(local_index[int(global_cells[0])])
				matrix[cell][cell] += g
				rhs[cell] += g * preferred
			"fixed_balance_terminal":
				var cell := int(local_index[int(global_cells[0])])
				rhs[cell] += float(element["law"].get("balance", 0.0))
			"linear_difference_coupler":
				var a_global := int(cell_map[_port_ref(element_id, "a")])
				var b_global := int(cell_map[_port_ref(element_id, "b")])
				if String(network["cells"][a_global]["domain"]) != String(network["cells"][b_global]["domain"]):
					var mismatch := {"ok": false, "code": "DIFFERENCE_COUPLER_DOMAIN_MISMATCH", "element_id": element_id}
					_mark_island_failed(network, island, String(mismatch["code"]))
					network["diagnostics"].append(mismatch)
					return mismatch
				var g := float(element["law"].get("response_gain", 0.0))
				var a := int(local_index[a_global])
				var b := int(local_index[b_global])
				if a != b:
					matrix[a][a] += g
					matrix[a][b] -= g
					matrix[b][a] -= g
					matrix[b][b] += g
			"ideal_common_constraint":
				var global_cell := int(global_cells[0])
				constraints.append({
					"kind": "ideal_common",
					"element_id": element_id,
					"row_index": 0,
					"value": float(element["law"].get("common", 0.0)),
					"terms": [{
						"cell": int(local_index[global_cell]),
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
					var names: Array = row.keys()
					names.sort()
					for port_name in names:
						var global_cell := int(cell_map[_port_ref(element_id, String(port_name))])
						terms.append({
							"cell": int(local_index[global_cell]),
							"global_cell": global_cell,
							"port_name": String(port_name),
							"coefficient": float(row[port_name]),
						})
					constraints.append({
						"kind": "power_map",
						"element_id": element_id,
						"row_index": row_index,
						"value": 0.0,
						"terms": terms,
					})
			"linear_storage_terminal":
				if delta <= 0.0:
					var dynamic_error := {"ok": false, "code": "DYNAMIC_ELEMENT_REQUIRES_STEP", "element_id": element_id}
					_mark_island_failed(network, island, String(dynamic_error["code"]))
					network["diagnostics"].append(dynamic_error)
					return dynamic_error
				var capacity := float(element["law"].get("capacity", 0.0))
				var g := capacity / delta
				var preferred := float(element["state"].get("common", 0.0))
				var cell := int(local_index[int(global_cells[0])])
				matrix[cell][cell] += g
				rhs[cell] += g * preferred
			_:
				var unknown := {"ok": false, "code": "UNKNOWN_PHYSICAL_LAW", "element_id": element_id, "op": op}
				_mark_island_failed(network, island, String(unknown["code"]))
				network["diagnostics"].append(unknown)
				return unknown

	var constraint_check := _validate_constraints(network, constraints)
	if not bool(constraint_check.get("ok", false)):
		_mark_island_failed(network, island, String(constraint_check["code"]))
		network["diagnostics"].append(constraint_check)
		return constraint_check

	var total_size := size + constraints.size()
	var augmented := _zero_matrix(total_size, total_size)
	var augmented_rhs := _zero_vector(total_size)
	for row in range(size):
		for col in range(size):
			augmented[row][col] = matrix[row][col]
		augmented_rhs[row] = rhs[row]

	for constraint_index in range(constraints.size()):
		var equation_row := size + constraint_index
		var constraint: Dictionary = constraints[constraint_index]
		for term in constraint["terms"]:
			var cell := int(term["cell"])
			var coefficient := float(term["coefficient"])
			augmented[cell][equation_row] += coefficient
			augmented[equation_row][cell] += coefficient
		augmented_rhs[equation_row] = float(constraint["value"])

	var solved := _solve_dense(augmented, augmented_rhs)
	if not bool(solved.get("ok", false)):
		var code := "SINGULAR_FLOATING_ISLAND" if constraints.is_empty() else "SINGULAR_OR_REDUNDANT_CONSTRAINT_SYSTEM"
		var singular := {"ok": false, "code": code, "cells": _cell_ids(network, island)}
		_mark_island_failed(network, island, code)
		network["diagnostics"].append(singular)
		return singular

	var solution: Array = solved["x"]
	for local in range(size):
		var global := int(island[local])
		network["cells"][global]["common"] = float(solution[local])
		network["cells"][global]["status"] = "SOLVED"

	var reactions := {}
	for constraint_index in range(constraints.size()):
		var constraint: Dictionary = constraints[constraint_index]
		var lambda := float(solution[size + constraint_index])
		var element_id := String(constraint["element_id"])
		if not reactions.has(element_id):
			reactions[element_id] = {}
		var row_lambdas: Array = network["elements"][element_id]["state"].get("constraint_lambdas", [])
		while row_lambdas.size() <= int(constraint["row_index"]):
			row_lambdas.append(0.0)
		row_lambdas[int(constraint["row_index"])] = lambda
		network["elements"][element_id]["state"]["constraint_lambdas"] = row_lambdas
		for term in constraint["terms"]:
			var port_name := String(term["port_name"])
			var reaction := -float(term["coefficient"]) * lambda
			reactions[element_id][port_name] = float(reactions[element_id].get(port_name, 0.0)) + reaction

	_apply_port_solution(network, cell_map, island, reactions, delta)
	_compute_cell_residuals(network, island)
	return {"ok": true, "cells": _cell_ids(network, island)}

static func _validate_constraints(network: Dictionary, constraints: Array) -> Dictionary:
	var by_cell := {}
	for constraint in constraints:
		if String(constraint.get("kind", "")) != "ideal_common":
			continue
		var term: Dictionary = constraint["terms"][0]
		var global_cell := int(term["global_cell"])
		if not by_cell.has(global_cell):
			by_cell[global_cell] = []
		by_cell[global_cell].append(constraint)
	var cells: Array = by_cell.keys()
	cells.sort()
	for global_cell in cells:
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

static func _apply_port_solution(
	network: Dictionary,
	cell_map: Dictionary,
	island: Array,
	reactions: Dictionary,
	delta: float
) -> void:
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

		var op := String(element["law"]["op"])
		match op:
			"equilibrium_terminal":
				var cell := int(cell_map[_port_ref(element_id, "p")])
				var common := float(network["cells"][cell]["common"])
				var g := float(element["law"]["response_gain"])
				var preferred := float(element["law"]["preferred_common"])
				_set_port_state(element, "p", common, g * (preferred - common))
			"fixed_balance_terminal":
				var cell := int(cell_map[_port_ref(element_id, "p")])
				_set_port_state(element, "p", float(network["cells"][cell]["common"]), float(element["law"]["balance"]))
			"linear_difference_coupler":
				var a_cell := int(cell_map[_port_ref(element_id, "a")])
				var b_cell := int(cell_map[_port_ref(element_id, "b")])
				var common_a := float(network["cells"][a_cell]["common"])
				var common_b := float(network["cells"][b_cell]["common"])
				var g := float(element["law"]["response_gain"])
				var transfer := g * (common_a - common_b)
				_set_port_state(element, "a", common_a, -transfer)
				_set_port_state(element, "b", common_b, transfer)
			"ideal_common_constraint", "linear_power_map":
				for port_name in port_names:
					var cell := int(cell_map[_port_ref(element_id, String(port_name))])
					var common := float(network["cells"][cell]["common"])
					var balance := float(reactions.get(element_id, {}).get(port_name, 0.0))
					_set_port_state(element, String(port_name), common, balance)
			"linear_storage_terminal":
				var cell := int(cell_map[_port_ref(element_id, "p")])
				var common := float(network["cells"][cell]["common"])
				var capacity := float(element["law"]["capacity"])
				var previous := float(element["state"]["common"])
				_set_port_state(element, "p", common, capacity / delta * (previous - common))

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
		var previous := float(element["state"]["common"])
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
			var element_id := String(parts[0])
			var port_name := String(parts[1])
			balance += float(network["elements"][element_id]["state"]["ports"][port_name]["balance"])
		cell["balance_residual"] = balance
		cell["power_residual"] = float(cell["common"]) * balance
		cell["status"] = "SOLVED"

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
			element["state"]["ports"][port_name] = {
				"common": 0.0,
				"balance": 0.0,
				"power_into_cell": 0.0,
			}

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
		"state": {
			"ports": port_states,
			"absorbed_power": 0.0,
		},
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
