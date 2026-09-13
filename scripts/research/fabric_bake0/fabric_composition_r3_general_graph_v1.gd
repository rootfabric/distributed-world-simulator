extends RefCounted

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const MAX_NODES := 32
const PIVOT_REL_TOL := 1.0e-14
const RESIDUAL_REL_TOL := 2.0e-10

static func solve_resistive(model: Dictionary, boundary_voltages_v: Dictionary) -> Dictionary:
	var node_ids: Array[String] = []
	var seen := {}
	for node in model.get("nodes", []):
		var node_id := str(node.get("node_id", ""))
		if node_id.is_empty() or seen.has(node_id): return U.failure("R3_GENERAL_ELECTRICAL_NODE_SET")
		seen[node_id] = true
		node_ids.append(node_id)
	node_ids.sort()
	if node_ids.is_empty() or node_ids.size() > MAX_NODES: return U.failure("R3_GENERAL_ELECTRICAL_NODE_SET")
	for key in boundary_voltages_v:
		if typeof(key) != TYPE_STRING or not seen.has(str(key)) or not U.is_finite_number(boundary_voltages_v[key]): return U.failure("R3_GENERAL_BOUNDARY_INVALID")
	if boundary_voltages_v.is_empty(): return U.failure("R3_GENERAL_BOUNDARY_REQUIRED")
	var adjacency := {}
	for node_id in node_ids: adjacency[node_id] = []
	var active_elements: Array = []
	for raw in model.get("elements", []):
		var element: Dictionary = raw
		if not bool(element.get("active", false)): continue
		var a := str(element.get("node_a", ""))
		var b := str(element.get("node_b", ""))
		if a == b or not adjacency.has(a) or not adjacency.has(b) or not U.is_positive_number(element.get("resistance_ohm")): return U.failure("R3_GENERAL_ELECTRICAL_ELEMENT_INVALID")
		adjacency[a].append(b)
		adjacency[b].append(a)
		active_elements.append(element)
	if active_elements.is_empty(): return U.failure("R3_GENERAL_OPEN_CIRCUIT")
	active_elements.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.element_id) < str(b.element_id))
	var unseen := {}
	for node_id in node_ids: unseen[node_id] = true
	for start in node_ids:
		if not unseen.has(start): continue
		var stack: Array[String] = [start]
		var has_boundary := false
		while not stack.is_empty():
			var node_id: String = stack.pop_back()
			if not unseen.has(node_id): continue
			unseen.erase(node_id)
			has_boundary = has_boundary or boundary_voltages_v.has(node_id)
			for neighbor in adjacency[node_id]:
				if unseen.has(neighbor): stack.append(str(neighbor))
		if not has_boundary: return U.failure("R3_GENERAL_FLOATING_COMPONENT")
	var free: Array[String] = []
	for node_id in node_ids:
		if not boundary_voltages_v.has(node_id): free.append(node_id)
	var index := {}
	for i in range(free.size()): index[free[i]] = i
	var matrix := _zero_matrix(free.size())
	var rhs := _zero_vector(free.size())
	for element in active_elements:
		var a: String = str(element.node_a)
		var b: String = str(element.node_b)
		var conductance := 1.0 / float(element.resistance_ohm)
		for pair in [[a, b], [b, a]]:
			var x: String = pair[0]
			var y: String = pair[1]
			if not index.has(x): continue
			var row: int = int(index[x])
			matrix[row][row] = float(matrix[row][row]) + conductance
			if index.has(y): matrix[row][int(index[y])] = float(matrix[row][int(index[y])]) - conductance
			else: rhs[row] = float(rhs[row]) + conductance * float(boundary_voltages_v[y])
	var solved := solve_dense(matrix, rhs)
	if not solved.success: return solved
	var potentials := {}
	for key in boundary_voltages_v: potentials[str(key)] = float(boundary_voltages_v[key])
	for i in range(free.size()): potentials[free[i]] = float(solved.details.x[i])
	var edge_currents := {}
	var balance := {}
	for node_id in node_ids: balance[node_id] = 0.0
	var joule := 0.0
	for element in active_elements:
		var a: String = str(element.node_a)
		var b: String = str(element.node_b)
		var resistance: float = float(element.resistance_ohm)
		var current := (float(potentials[a]) - float(potentials[b])) / resistance
		edge_currents[str(element.element_id)] = current
		balance[a] = float(balance[a]) + current
		balance[b] = float(balance[b]) - current
		joule += current * current * resistance
	var ports := {}
	var max_kcl := 0.0
	for node_id in node_ids:
		if boundary_voltages_v.has(node_id): ports[node_id] = float(balance[node_id])
		else: max_kcl = maxf(max_kcl, absf(float(balance[node_id])))
	var boundary_power := 0.0
	for node_id in ports: boundary_power += float(potentials[node_id]) * float(ports[node_id])
	var power_residual := absf(boundary_power - joule)
	var current_scale := 1.0
	for value in edge_currents.values(): current_scale = maxf(current_scale, absf(float(value)))
	for value in ports.values(): current_scale = maxf(current_scale, absf(float(value)))
	var power_scale := 1.0 + absf(boundary_power) + absf(joule)
	if max_kcl > RESIDUAL_REL_TOL * current_scale or power_residual > RESIDUAL_REL_TOL * power_scale:
		return U.failure("R3_GENERAL_GRAPH_RESIDUAL", {"kcl_residual_a": max_kcl, "power_residual_w": power_residual})
	return U.success({"potentials_v": potentials, "edge_currents_a": edge_currents, "port_currents_a": ports, "kcl_residual_a": max_kcl, "joule_power_w": joule, "boundary_power_w": boundary_power, "power_residual_w": power_residual, "pivot_condition_estimate": float(solved.details.pivot_condition_estimate)})

static func boundary_for_velocity(boundaries: Dictionary, source_port_id: String, coupling: float, velocity: float) -> Dictionary:
	var result: Dictionary = boundaries.duplicate(true)
	result[source_port_id] = float(result[source_port_id]) - coupling * velocity
	return result

static func external_power(nominal_boundaries: Dictionary, port_currents: Dictionary) -> float:
	var result := 0.0
	for node_id in port_currents: result += float(nominal_boundaries[node_id]) * float(port_currents[node_id])
	return result

static func solve_dense(matrix: Array, rhs: Array) -> Dictionary:
	var n := rhs.size()
	if matrix.size() != n: return U.failure("R3_GENERAL_LINEAR_SHAPE")
	if n == 0: return U.success({"x": [], "pivot_condition_estimate": 1.0})
	var augmented: Array = []
	var global_scale := 0.0
	for i in range(n):
		if not matrix[i] is Array or matrix[i].size() != n: return U.failure("R3_GENERAL_LINEAR_SHAPE")
		var row: Array = []
		for j in range(n):
			var value := float(matrix[i][j])
			if not is_finite(value): return U.failure("R3_GENERAL_LINEAR_NONFINITE")
			global_scale = maxf(global_scale, absf(value))
			row.append(value)
		var b := float(rhs[i])
		if not is_finite(b): return U.failure("R3_GENERAL_LINEAR_NONFINITE")
		row.append(b)
		augmented.append(row)
	if global_scale == 0.0: return U.failure("R3_GENERAL_SINGULAR_SYSTEM")
	var min_pivot := INF
	var max_pivot := 0.0
	for column in range(n):
		var pivot_row := column
		var pivot_abs := absf(float(augmented[column][column]))
		for row in range(column + 1, n):
			var candidate := absf(float(augmented[row][column]))
			if candidate > pivot_abs:
				pivot_abs = candidate
				pivot_row = row
		if pivot_abs <= PIVOT_REL_TOL * global_scale: return U.failure("R3_GENERAL_SINGULAR_SYSTEM")
		if pivot_row != column:
			var temp = augmented[column]
			augmented[column] = augmented[pivot_row]
			augmented[pivot_row] = temp
		var pivot := float(augmented[column][column])
		min_pivot = minf(min_pivot, absf(pivot))
		max_pivot = maxf(max_pivot, absf(pivot))
		for row in range(column + 1, n):
			var factor := float(augmented[row][column]) / pivot
			augmented[row][column] = 0.0
			for j in range(column + 1, n + 1): augmented[row][j] = float(augmented[row][j]) - factor * float(augmented[column][j])
	var x := _zero_vector(n)
	for row in range(n - 1, -1, -1):
		var value := float(augmented[row][n])
		for j in range(row + 1, n): value -= float(augmented[row][j]) * float(x[j])
		x[row] = value / float(augmented[row][row])
		if not is_finite(float(x[row])): return U.failure("R3_GENERAL_LINEAR_NONFINITE")
	return U.success({"x": x, "pivot_condition_estimate": max_pivot / maxf(min_pivot, 1.0e-300)})

static func _zero_vector(size: int) -> Array:
	var result: Array = []
	for _i in range(size): result.append(0.0)
	return result

static func _zero_matrix(size: int) -> Array:
	var result: Array = []
	for _i in range(size): result.append(_zero_vector(size))
	return result
