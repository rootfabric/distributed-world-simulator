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
		if not is_finite(conductance):
			return U.failure("R3_NUMERIC_ENVELOPE", {"stage": "conductance", "element_id": str(element.element_id)})
		for pair in [[a, b], [b, a]]:
			var x: String = pair[0]
			var y: String = pair[1]
			if not index.has(x): continue
			var row: int = int(index[x])
			var assembled_diagonal := float(matrix[row][row]) + conductance
			if not is_finite(assembled_diagonal): return U.failure("R3_NUMERIC_ENVELOPE", {"stage": "matrix_diagonal", "element_id": str(element.element_id)})
			matrix[row][row] = assembled_diagonal
			if index.has(y):
				var assembled := float(matrix[row][int(index[y])]) - conductance
				if not is_finite(assembled): return U.failure("R3_NUMERIC_ENVELOPE", {"stage": "matrix", "element_id": str(element.element_id)})
				matrix[row][int(index[y])] = assembled
			else:
				var rhs_term := conductance * float(boundary_voltages_v[y])
				var assembled_rhs := float(rhs[row]) + rhs_term
				if not is_finite(rhs_term) or not is_finite(assembled_rhs): return U.failure("R3_NUMERIC_ENVELOPE", {"stage": "rhs", "element_id": str(element.element_id)})
				rhs[row] = assembled_rhs
	var solved := solve_dense(matrix, rhs)
	if not solved.success: return solved
	var potentials := {}
	for key in boundary_voltages_v: potentials[str(key)] = float(boundary_voltages_v[key])
	for i in range(free.size()):
		var potential := float(solved.details.x[i])
		if not is_finite(potential): return U.failure("R3_NUMERIC_ENVELOPE", {"stage": "potential", "node_id": free[i]})
		potentials[free[i]] = potential
	if not is_finite(float(solved.details.pivot_condition_estimate)):
		return U.failure("R3_NUMERIC_ENVELOPE", {"stage": "condition_estimate"})
	var edge_currents := {}
	var balance_terms := {}
	for node_id in node_ids: balance_terms[node_id] = []
	var joule := 0.0
	for element in active_elements:
		var a: String = str(element.node_a)
		var b: String = str(element.node_b)
		var resistance: float = float(element.resistance_ohm)
		var delta_v := float(potentials[a]) - float(potentials[b])
		var current := delta_v / resistance
		if not is_finite(delta_v) or not is_finite(current):
			return U.failure("R3_NUMERIC_ENVELOPE", {"stage": "edge_current", "element_id": str(element.element_id)})
		edge_currents[str(element.element_id)] = current
		balance_terms[a].append(current)
		balance_terms[b].append(-current)
		# delta_v * current is algebraically equal to I^2 R but avoids an
		# avoidable intermediate overflow when both final factors remain finite.
		var joule_term := delta_v * current
		var next_joule := joule + joule_term
		if not is_finite(joule_term) or not is_finite(next_joule):
			return U.failure("R3_NUMERIC_ENVELOPE", {"stage": "joule_power", "element_id": str(element.element_id)})
		joule = next_joule
	var balance := {}
	for node_id in node_ids:
		var summed_balance := _safe_signed_sum(balance_terms[node_id])
		if not bool(summed_balance.get("success", false)):
			return U.failure("R3_NUMERIC_ENVELOPE", {"stage": "node_balance", "node_id": node_id})
		balance[node_id] = float(summed_balance.value)
	var ports := {}
	var max_kcl := 0.0
	for node_id in node_ids:
		if boundary_voltages_v.has(node_id): ports[node_id] = float(balance[node_id])
		else: max_kcl = maxf(max_kcl, absf(float(balance[node_id])))
	var boundary_power_result := _safe_dot_sum_for_power(potentials, ports)
	if not bool(boundary_power_result.get("success", false)):
		return U.failure("R3_NUMERIC_ENVELOPE", {"stage": "boundary_power"})
	var boundary_power := float(boundary_power_result.value)
	var power_residual := absf(boundary_power - joule)
	if not is_finite(max_kcl) or not is_finite(power_residual):
		return U.failure("R3_NUMERIC_ENVELOPE", {"stage": "residual", "kcl_residual_a": max_kcl, "power_residual_w": power_residual})
	var current_scale := 1.0
	for value in edge_currents.values(): current_scale = maxf(current_scale, absf(float(value)))
	for value in ports.values(): current_scale = maxf(current_scale, absf(float(value)))
	# Max-based scaling cannot overflow merely because two finite powers are large.
	var power_scale := maxf(1.0, maxf(absf(boundary_power), absf(joule)))
	if not is_finite(current_scale) or not is_finite(power_scale):
		return U.failure("R3_NUMERIC_ENVELOPE", {"stage": "residual_scale"})
	if max_kcl > RESIDUAL_REL_TOL * current_scale or power_residual > RESIDUAL_REL_TOL * power_scale:
		return U.failure("R3_GENERAL_GRAPH_RESIDUAL", {"kcl_residual_a": max_kcl, "power_residual_w": power_residual})
	return U.success({"potentials_v": potentials, "edge_currents_a": edge_currents, "port_currents_a": ports, "kcl_residual_a": max_kcl, "joule_power_w": joule, "boundary_power_w": boundary_power, "power_residual_w": power_residual, "pivot_condition_estimate": float(solved.details.pivot_condition_estimate)})

static func boundary_for_velocity(boundaries: Dictionary, source_port_id: String, coupling: float, velocity: float) -> Dictionary:
	var result: Dictionary = boundaries.duplicate(true)
	result[source_port_id] = float(result[source_port_id]) - coupling * velocity
	return result

static func external_power(nominal_boundaries: Dictionary, port_currents: Dictionary) -> float:
	var solved := _safe_dot_sum_for_power(nominal_boundaries, port_currents)
	return float(solved.value) if bool(solved.get("success", false)) else INF

# Preserve the original arithmetic path whenever it remains finite. Only the
# overflow case falls back to scale-normalized compensated summation, so
# nominal historical hashes do not move merely because this guard exists.
static func _safe_signed_sum(values: Array) -> Dictionary:
	var naive := 0.0
	var naive_ok := true
	for raw_value in values:
		var value := float(raw_value)
		if not is_finite(value): return {"success": false}
		if naive_ok:
			var next_value := naive + value
			if is_finite(next_value): naive = next_value
			else: naive_ok = false
	if naive_ok: return {"success": true, "value": naive}
	var scale := 0.0
	for raw_value in values: scale = maxf(scale, absf(float(raw_value)))
	if not is_finite(scale): return {"success": false}
	if scale == 0.0: return {"success": true, "value": 0.0}
	var total := 0.0
	var correction := 0.0
	for raw_value in values:
		var normalized := float(raw_value) / scale
		var y := normalized - correction
		var next_total := total + y
		correction = (next_total - total) - y
		total = next_total
	var result := total * scale
	if not is_finite(result): return {"success": false}
	return {"success": true, "value": result}

static func _safe_dot_sum_for_power(left: Dictionary, right: Dictionary) -> Dictionary:
	var keys: Array[String] = []
	for raw_key in right:
		var key := str(raw_key)
		if not left.has(key): return {"success": false}
		keys.append(key)
	keys.sort()
	var naive := 0.0
	var naive_ok := true
	for key in keys:
		var a := float(left[key])
		var b := float(right[key])
		if not is_finite(a) or not is_finite(b): return {"success": false}
		if naive_ok:
			var term := a * b
			var next_value := naive + term
			if is_finite(term) and is_finite(next_value): naive = next_value
			else: naive_ok = false
	if naive_ok: return {"success": true, "value": naive}
	var left_scale := 0.0
	var right_scale := 0.0
	for key in keys:
		left_scale = maxf(left_scale, absf(float(left[key])))
		right_scale = maxf(right_scale, absf(float(right[key])))
	if not is_finite(left_scale) or not is_finite(right_scale): return {"success": false}
	if left_scale == 0.0 or right_scale == 0.0: return {"success": true, "value": 0.0}
	var normalized_terms: Array = []
	for key in keys:
		normalized_terms.append((float(left[key]) / left_scale) * (float(right[key]) / right_scale))
	var normalized_sum := _safe_signed_sum(normalized_terms)
	if not bool(normalized_sum.get("success", false)): return {"success": false}
	var first_scale := minf(left_scale, right_scale)
	var second_scale := maxf(left_scale, right_scale)
	var intermediate := float(normalized_sum.value) * first_scale
	if not is_finite(intermediate): return {"success": false}
	var result := intermediate * second_scale
	if not is_finite(result): return {"success": false}
	return {"success": true, "value": result}

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
	var condition_estimate := max_pivot / maxf(min_pivot, 1.0e-300)
	if not is_finite(condition_estimate): return U.failure("R3_GENERAL_LINEAR_NONFINITE")
	return U.success({"x": x, "pivot_condition_estimate": condition_estimate})

static func _zero_vector(size: int) -> Array:
	var result: Array = []
	for _i in range(size): result.append(0.0)
	return result

static func _zero_matrix(size: int) -> Array:
	var result: Array = []
	for _i in range(size): result.append(_zero_vector(size))
	return result
