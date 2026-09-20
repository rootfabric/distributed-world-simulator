extends RefCounted

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/fabric_composition_r3_general_graph_v1.gd")
const MAX_NODES := 32
const COLLINEAR_TOL := 1.0e-10
const COUPLER_FIELD := "coupler_node_id"
const MIN_DAE_DIVISOR := 1.0e-15

static func solve_mechanical_static(model: Dictionary, coupler_node_id: String) -> Dictionary:
	var anchored := {}
	var mobile: Array[String] = []
	for node in model.get("nodes", []):
		var node_id := str(node.get("node_id", ""))
		if node_id.is_empty() or anchored.has(node_id): return U.failure("R3_GENERAL_MECHANICAL_NODE_SET")
		anchored[node_id] = bool(node.get("anchored", false))
		if not bool(node.get("anchored", false)): mobile.append(node_id)
	mobile.sort()
	if mobile.is_empty() or not mobile.has(coupler_node_id): return U.failure("R3_GENERAL_COUPLER_NODE_REQUIRED")
	var index := {}
	for i in range(mobile.size()): index[mobile[i]] = i
	var matrix: Array = Graph._zero_matrix(mobile.size())
	var active: Array = []
	for element in model.get("elements", []):
		if bool(element.get("active", false)): active.append(element)
	active.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.element_id) < str(b.element_id))
	for element in active:
		var a := str(element.node_a)
		var b := str(element.node_b)
		if not anchored.has(a) or not anchored.has(b) or not U.is_positive_number(element.get("stiffness_n_per_m")):
			return U.failure("R3_GENERAL_MECHANICAL_ELEMENT_INVALID")
		var stiffness: float = float(element.stiffness_n_per_m)
		for pair in [[a, b], [b, a]]:
			var x: String = pair[0]
			var y: String = pair[1]
			if not index.has(x): continue
			var row: int = int(index[x])
			matrix[row][row] = float(matrix[row][row]) + stiffness
			if index.has(y): matrix[row][int(index[y])] = float(matrix[row][int(index[y])]) - stiffness
	var rhs: Array = Graph._zero_vector(mobile.size())
	rhs[int(index[coupler_node_id])] = 1.0
	var solved := Graph.solve_dense(matrix, rhs)
	if not solved.success: return U.failure("R3_GENERAL_MECHANICAL_UNDERDETERMINED", solved.details)
	var displacement := {}
	for i in range(mobile.size()): displacement[mobile[i]] = float(solved.details.x[i])
	return U.success({"mobile_nodes": mobile, "displacement_per_newton": displacement, "pivot_condition_estimate": solved.details.pivot_condition_estimate})

static func compile_mechanics(model: Dictionary, controls: Dictionary) -> Dictionary:
	var nodes := {}
	var mobile_nodes: Array[String] = []
	var masses: Dictionary = {}
	for node in model.nodes:
		var node_id := str(node.node_id)
		if node_id.is_empty() or nodes.has(node_id) or not U.is_positive_number(node.mass_kg) or float(node.mass_kg) <= MIN_DAE_DIVISOR: return U.failure("R3_MASS_INVALID")
		nodes[node_id] = node
		if not bool(node.anchored):
			mobile_nodes.append(node_id)
			masses[node_id] = float(node.mass_kg)
	mobile_nodes.sort()
	if mobile_nodes.is_empty() or mobile_nodes.size() > MAX_NODES: return U.failure("R3_GENERAL_MOBILE_NODE_COUNT")
	var coupler := str(controls.get(COUPLER_FIELD, ""))
	if coupler.is_empty() and mobile_nodes.size() == 1: coupler = mobile_nodes[0]
	if not mobile_nodes.has(coupler): return U.failure("R3_GENERAL_COUPLER_NODE_REQUIRED")
	var row_k := {}
	var row_c := {}
	for node_id in mobile_nodes:
		row_k[node_id] = 0.0
		row_c[node_id] = 0.0
	var elements: Array = model.elements.duplicate()
	elements.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.element_id) < str(b.element_id))
	var have_geometry := false
	var minimum_position := Vector3.ZERO
	var maximum_position := Vector3.ZERO
	for element in elements:
		if not U.is_positive_number(element.capacity_n) or float(element.capacity_n) < 1.0e-6: return U.failure("R3_CAPACITY_BELOW_EVENT_RESOLUTION")
		if not element.active: continue
		var a: String = str(element.node_a)
		var b: String = str(element.node_b)
		if not nodes.has(a) or not nodes.has(b): return U.failure("R3_GENERAL_MECHANICAL_ENDPOINT")
		var position_a := _vector(nodes[a].local_position_m)
		var position_b := _vector(nodes[b].local_position_m)
		var delta := position_b - position_a
		if delta.length() <= 1.0e-12: return U.failure("R3_GENERAL_MECHANICAL_ZERO_LENGTH")
		for position in [position_a, position_b]:
			if not have_geometry:
				minimum_position = position
				maximum_position = position
				have_geometry = true
			elif _position_less(position, minimum_position): minimum_position = position
			elif _position_less(maximum_position, position): maximum_position = position
		for node_id in [a, b]:
			if row_k.has(node_id):
				row_k[node_id] = float(row_k[node_id]) + float(element.stiffness_n_per_m)
				row_c[node_id] = float(row_c[node_id]) + float(element.damping_ns_per_m)
	if not have_geometry: return U.failure("R3_GENERAL_MECHANICAL_ELEMENT_SET")
	var span := maximum_position - minimum_position
	if span.length() <= 1.0e-12: return U.failure("R3_GENERAL_MECHANICAL_ZERO_LENGTH")
	var axis := span.normalized()
	for element in elements:
		if not element.active: continue
		var delta := _vector(nodes[str(element.node_b)].local_position_m) - _vector(nodes[str(element.node_a)].local_position_m)
		if absf(delta.normalized().dot(axis)) < 1.0 - COLLINEAR_TOL: return U.failure("R3_GENERAL_COLLINEAR_AXIAL_REQUIRED")
	var static_check := solve_mechanical_static(model, coupler)
	if not static_check.success: return static_check
	var mobile_index := {}
	var mobile_masses: Array = []
	var rate := 0.0
	for i in range(mobile_nodes.size()):
		var node_id: String = mobile_nodes[i]
		mobile_index[node_id] = i
		var mass: float = float(masses[node_id])
		mobile_masses.append(mass)
		rate = maxf(rate, sqrt(maxf(0.0, float(row_k[node_id])) / mass) + float(row_c[node_id]) / mass)
	if not is_finite(rate): return U.failure("R3_NUMERIC_ENVELOPE")
	return U.success({"axis": [axis.x, axis.y, axis.z], "mobile_nodes": mobile_nodes, "mobile_index": mobile_index, "mobile_masses_kg": mobile_masses, "coupler_node_id": coupler, "rate_bound": rate})

static func _position_less(a: Vector3, b: Vector3) -> bool:
	if a.x != b.x: return a.x < b.x
	if a.y != b.y: return a.y < b.y
	return a.z < b.z

static func _vector(position: Array) -> Vector3:
	return Vector3(float(position[0]), float(position[1]), float(position[2]))
