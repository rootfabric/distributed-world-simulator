extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/structural_aggregate_descriptor_v1.gd")
const Reconstruction = preload("res://scripts/research/fabric_bake0/structural_reconstruction_mapping_v1.gd")

const READY_FOR_GUARDS := "STRUCTURAL_AGGREGATE_READY_FOR_GUARDS"
const REQUEST_FIELDS: Array[String] = [
	"descriptor_id", "mapping_id", "source_frontier_hash", "construct_id", "parts", "bonds",
	"boundary_anchors", "reconstruction_version", "minimum_part_count",
]
const PART_FIELDS: Array[String] = [
	"part_id", "region_id", "mass", "position", "orientation", "inertia_tensor", "support_points",
]
const BOND_FIELDS: Array[String] = ["bond_id", "part_a", "part_b", "rigid"]
const ANCHOR_FIELDS: Array[String] = ["anchor_id", "part_id", "position_local", "orientation_local"]
const DEFAULT_MINIMUM_PART_COUNT := 100
const MATRIX_TOLERANCE := 1.0e-10

static func compile(request: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(request, REQUEST_FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	for field in ["descriptor_id", "mapping_id", "construct_id"]:
		if not Utils.is_canonical_id(request.get(field), 2):
			return Utils.failure("INVALID_STRUCTURAL_COMPILE_ID", {"field": field})
	if not Utils.is_lower_hex_64(request.get("source_frontier_hash")):
		return Utils.failure("INVALID_STRUCTURAL_SOURCE_FRONTIER_HASH")
	if typeof(request.get("reconstruction_version")) != TYPE_STRING or String(request["reconstruction_version"]).strip_edges().is_empty():
		return Utils.failure("INVALID_STRUCTURAL_RECONSTRUCTION_VERSION")
	if not Utils.is_json_integer(request.get("minimum_part_count")) or int(request["minimum_part_count"]) < 2:
		return Utils.failure("INVALID_STRUCTURAL_MINIMUM_PART_COUNT")
	if typeof(request.get("parts")) != TYPE_ARRAY or typeof(request.get("bonds")) != TYPE_ARRAY or typeof(request.get("boundary_anchors")) != TYPE_ARRAY:
		return Utils.failure("INVALID_STRUCTURAL_COMPILE_COLLECTION")
	var minimum_part_count := maxi(DEFAULT_MINIMUM_PART_COUNT, int(request["minimum_part_count"]))
	if request["parts"].size() < minimum_part_count:
		return Utils.failure("INSUFFICIENT_STRUCTURAL_COMPLEXITY_REDUCTION", {"part_count": request["parts"].size(), "minimum": minimum_part_count})
	var parts := Utils.sorted_dicts(request["parts"], "part_id")
	var bonds := Utils.sorted_dicts(request["bonds"], "bond_id")
	var anchors := Utils.sorted_dicts(request["boundary_anchors"], "anchor_id")
	var part_by_id: Dictionary = {}
	var total_mass := 0.0
	var weighted_position := Vector3.ZERO
	var region_parts: Dictionary = {}
	for index in range(parts.size()):
		var part: Dictionary = parts[index]
		checked = _validate_part(part)
		if not bool(checked.get("success", false)):
			return checked
		var part_id := String(part["part_id"])
		if part_by_id.has(part_id):
			return Utils.failure("DUPLICATE_STRUCTURAL_PART", {"part_id": part_id})
		part_by_id[part_id] = part
		var mass := float(part["mass"])
		total_mass += mass
		weighted_position += _vec3(part["position"]) * mass
		var region_id := String(part["region_id"])
		if not region_parts.has(region_id):
			region_parts[region_id] = []
		region_parts[region_id].append(part_id)
	if total_mass <= 0.0 or not is_finite(total_mass):
		return Utils.failure("INVALID_STRUCTURAL_TOTAL_MASS")
	var center_of_mass := weighted_position / total_mass
	checked = _validate_bonds_connected_rigid(bonds, part_by_id)
	if not bool(checked.get("success", false)):
		return checked
	if anchors.is_empty():
		return Utils.failure("STRUCTURAL_BOUNDARY_ANCHORS_REQUIRED")
	for anchor in anchors:
		checked = _validate_anchor(anchor, part_by_id)
		if not bool(checked.get("success", false)):
			return checked
	var inertia := _zero3()
	var part_mappings: Array = []
	var support_points: Array = []
	for part in parts:
		var part_q := _quat(part["orientation"])
		var part_position := _vec3(part["position"])
		var offset := part_position - center_of_mass
		var rotation := _rotation_matrix(part_q)
		var rotated_inertia := _mat_mul(_mat_mul(rotation, part["inertia_tensor"]), _mat_transpose(rotation))
		var parallel_axis := _parallel_axis(float(part["mass"]), offset)
		inertia = _mat_add(inertia, _mat_add(rotated_inertia, parallel_axis))
		part_mappings.append({
			"part_id": String(part["part_id"]),
			"region_id": String(part["region_id"]),
			"position_from_com": _arr3(offset),
			"orientation_from_aggregate": _arr4(part_q),
		})
		for point_index in range(part["support_points"].size()):
			var point_local := _vec3(part["support_points"][point_index])
			var point_from_com := offset + part_q * point_local
			support_points.append({
				"point_id": "%s#%04d" % [String(part["part_id"]), point_index],
				"part_id": String(part["part_id"]),
				"point_from_com": _arr3(point_from_com),
			})
	var region_mappings: Array = []
	var region_ids: Array = region_parts.keys()
	region_ids.sort()
	for region_id in region_ids:
		var part_ids: Array = region_parts[region_id]
		part_ids.sort()
		region_mappings.append({"region_id": String(region_id), "part_ids": part_ids})
	var full_state_schema_hash := Utils.canonical_hash({
		"schema": "planet_simulator.fabric_bake_structural_full_rigid_state.v1",
		"per_part_fields": ["position", "orientation", "linear_velocity", "angular_velocity"],
	})
	var reduced_state_schema_hash := Utils.canonical_hash({
		"schema": "planet_simulator.fabric_bake_structural_reduced_rigid_state.v1",
		"fields": ["position", "orientation", "linear_velocity", "angular_velocity"],
		"frame_origin": "CENTER_OF_MASS",
	})
	var mapping := Reconstruction.create(
		String(request["mapping_id"]), String(request["source_frontier_hash"]), String(request["construct_id"]),
		String(parts[0]["part_id"]), full_state_schema_hash, reduced_state_schema_hash,
		part_mappings, region_mappings, String(request["reconstruction_version"])
	)
	if mapping.is_empty():
		return Utils.failure("STRUCTURAL_RECONSTRUCTION_MAPPING_ASSEMBLY_FAILED")
	var compiled_anchors: Array = []
	for anchor in anchors:
		var part: Dictionary = part_by_id[String(anchor["part_id"])]
		var part_q := _quat(part["orientation"])
		var position_from_com := _vec3(part["position"]) - center_of_mass + part_q * _vec3(anchor["position_local"])
		var orientation_from_aggregate := _canonical_quat(part_q * _quat(anchor["orientation_local"]))
		compiled_anchors.append({
			"anchor_id": String(anchor["anchor_id"]),
			"part_id": String(anchor["part_id"]),
			"position_from_com": _arr3(position_from_com),
			"orientation_from_aggregate": _arr4(orientation_from_aggregate),
			"linear_velocity_jacobian_body": _rigid_point_jacobian(position_from_com),
		})
	var descriptor := Descriptor.create(
		String(request["descriptor_id"]), String(request["source_frontier_hash"]), String(request["construct_id"]),
		parts.size(), bonds.size(), region_mappings.size(), total_mass, _arr3(center_of_mass), inertia,
		compiled_anchors, {"kind": "FINITE_SUPPORT_SET", "points": support_points},
		full_state_schema_hash, reduced_state_schema_hash, String(mapping["checksum"])
	)
	if descriptor.is_empty():
		return Utils.failure("STRUCTURAL_AGGREGATE_DESCRIPTOR_ASSEMBLY_FAILED")
	return {
		"success": true,
		"status": READY_FOR_GUARDS,
		"descriptor": descriptor,
		"reconstruction_mapping": mapping,
		"diagnostics": {
			"part_count": parts.size(),
			"bond_count": bonds.size(),
			"region_count": region_mappings.size(),
			"support_point_count": support_points.size(),
			"state_reduction_ratio": float(parts.size()),
			"physical_bake_artifact_emitted": false,
			"next_required_stage": "B0.2-C_REFINEMENT_GUARDS",
		},
	}

static func evaluate_anchor(descriptor: Dictionary, reduced_state: Dictionary, anchor_id: String) -> Dictionary:
	var checked := Descriptor.validate(descriptor)
	if not bool(checked.get("success", false)):
		return checked
	checked = _validate_reduced_state(reduced_state)
	if not bool(checked.get("success", false)):
		return checked
	var anchor: Dictionary = {}
	for candidate in descriptor["boundary_anchors"]:
		if String(candidate["anchor_id"]) == anchor_id:
			anchor = candidate
			break
	if anchor.is_empty():
		return Utils.failure("STRUCTURAL_BOUNDARY_ANCHOR_NOT_FOUND", {"anchor_id": anchor_id})
	var q := _quat(reduced_state["orientation"])
	var world_r := q * _vec3(anchor["position_from_com"])
	var omega := _vec3(reduced_state["angular_velocity"])
	return Utils.success({
		"position": _arr3(_vec3(reduced_state["position"]) + world_r),
		"orientation": _arr4(_canonical_quat(q * _quat(anchor["orientation_from_aggregate"]))),
		"linear_velocity": _arr3(_vec3(reduced_state["linear_velocity"]) + omega.cross(world_r)),
		"angular_velocity": _arr3(omega),
		"linear_velocity_jacobian_world": _rigid_point_jacobian(world_r),
	})

static func support(descriptor: Dictionary, direction_body: Array) -> Dictionary:
	var checked := Descriptor.validate(descriptor)
	if not bool(checked.get("success", false)):
		return checked
	checked = _validate_vec3(direction_body)
	if not bool(checked.get("success", false)):
		return checked
	var direction := _vec3(direction_body)
	if direction.length_squared() <= 0.0:
		return Utils.failure("ZERO_STRUCTURAL_SUPPORT_DIRECTION")
	var best_dot := -INF
	var best: Dictionary = {}
	for point in descriptor["support_envelope"]["points"]:
		var score := direction.dot(_vec3(point["point_from_com"]))
		if score > best_dot:
			best_dot = score
			best = point
	return Utils.success({"point": best["point_from_com"].duplicate(), "point_id": String(best["point_id"]), "support": best_dot})

static func full_momentum(parts: Array, full_states: Dictionary, com_world: Array) -> Dictionary:
	var com := _vec3(com_world)
	var linear := Vector3.ZERO
	var angular := Vector3.ZERO
	for part in parts:
		if typeof(part) != TYPE_DICTIONARY or not full_states.has(String(part.get("part_id", ""))):
			return Utils.failure("STRUCTURAL_MOMENTUM_INPUT_MISMATCH")
		var state: Dictionary = full_states[String(part["part_id"])]
		var mass := float(part["mass"])
		var position := _vec3(state["position"])
		var velocity := _vec3(state["linear_velocity"])
		var omega := _vec3(state["angular_velocity"])
		var momentum := velocity * mass
		linear += momentum
		var rotation := _rotation_matrix(_quat(state["orientation"]))
		var inertia_world := _mat_mul(_mat_mul(rotation, part["inertia_tensor"]), _mat_transpose(rotation))
		angular += (position - com).cross(momentum) + _mat_vec(inertia_world, omega)
	return Utils.success({"linear_momentum": _arr3(linear), "angular_momentum_about_com": _arr3(angular)})

static func reduced_momentum(descriptor: Dictionary, reduced_state: Dictionary) -> Dictionary:
	var checked := Descriptor.validate(descriptor)
	if not bool(checked.get("success", false)):
		return checked
	checked = _validate_reduced_state(reduced_state)
	if not bool(checked.get("success", false)):
		return checked
	var q := _quat(reduced_state["orientation"])
	var rotation := _rotation_matrix(q)
	var inertia_world := _mat_mul(_mat_mul(rotation, descriptor["inertia_tensor_body"]), _mat_transpose(rotation))
	var linear := _vec3(reduced_state["linear_velocity"]) * float(descriptor["total_mass"])
	var angular := _mat_vec(inertia_world, _vec3(reduced_state["angular_velocity"]))
	return Utils.success({"linear_momentum": _arr3(linear), "angular_momentum_about_com": _arr3(angular)})

static func _validate_part(part: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(part, PART_FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if not Utils.is_canonical_id(part.get("part_id"), 2) or not Utils.is_canonical_id(part.get("region_id"), 2):
		return Utils.failure("INVALID_STRUCTURAL_PART_ID")
	if not Utils.is_positive_number(part.get("mass")):
		return Utils.failure("INVALID_STRUCTURAL_PART_MASS", {"part_id": part.get("part_id", "")})
	checked = _validate_vec3(part.get("position"))
	if not bool(checked.get("success", false)):
		return checked
	checked = _validate_quat(part.get("orientation"))
	if not bool(checked.get("success", false)):
		return checked
	checked = _validate_spd_matrix3(part.get("inertia_tensor"))
	if not bool(checked.get("success", false)):
		return checked
	if typeof(part.get("support_points")) != TYPE_ARRAY or part["support_points"].is_empty():
		return Utils.failure("STRUCTURAL_PART_SUPPORT_REQUIRED", {"part_id": part["part_id"]})
	for point in part["support_points"]:
		checked = _validate_vec3(point)
		if not bool(checked.get("success", false)):
			return checked
	return Utils.success()

static func _validate_anchor(anchor: Dictionary, part_by_id: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(anchor, ANCHOR_FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if not Utils.is_canonical_id(anchor.get("anchor_id"), 2) or not Utils.is_canonical_id(anchor.get("part_id"), 2):
		return Utils.failure("INVALID_STRUCTURAL_BOUNDARY_ANCHOR_ID")
	if not part_by_id.has(String(anchor["part_id"])):
		return Utils.failure("STRUCTURAL_BOUNDARY_ANCHOR_PART_MISSING", {"part_id": anchor["part_id"]})
	checked = _validate_vec3(anchor.get("position_local"))
	if not bool(checked.get("success", false)):
		return checked
	return _validate_quat(anchor.get("orientation_local"))

static func _validate_bonds_connected_rigid(bonds: Array, part_by_id: Dictionary) -> Dictionary:
	if bonds.is_empty():
		return Utils.failure("STRUCTURAL_RIGID_BONDS_REQUIRED")
	var adjacency: Dictionary = {}
	for part_id in part_by_id.keys():
		adjacency[part_id] = []
	var bond_ids: Dictionary = {}
	for bond in bonds:
		var checked := Utils.validate_exact_fields(bond, BOND_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		if not Utils.is_canonical_id(bond.get("bond_id"), 2):
			return Utils.failure("INVALID_STRUCTURAL_BOND_ID")
		var bond_id := String(bond["bond_id"])
		if bond_ids.has(bond_id):
			return Utils.failure("DUPLICATE_STRUCTURAL_BOND", {"bond_id": bond_id})
		bond_ids[bond_id] = true
		if typeof(bond.get("rigid")) != TYPE_BOOL or not bool(bond["rigid"]):
			return Utils.failure("NON_RIGID_STRUCTURAL_BOND", {"bond_id": bond_id})
		var part_a := String(bond["part_a"])
		var part_b := String(bond["part_b"])
		if part_a == part_b or not part_by_id.has(part_a) or not part_by_id.has(part_b):
			return Utils.failure("INVALID_STRUCTURAL_BOND_ENDPOINT", {"bond_id": bond_id})
		adjacency[part_a].append(part_b)
		adjacency[part_b].append(part_a)
	var start := String(part_by_id.keys()[0])
	var queue: Array = [start]
	var visited: Dictionary = {start: true}
	while not queue.is_empty():
		var current := String(queue.pop_front())
		for neighbor in adjacency[current]:
			var neighbor_id := String(neighbor)
			if not visited.has(neighbor_id):
				visited[neighbor_id] = true
				queue.append(neighbor_id)
	if visited.size() != part_by_id.size():
		return Utils.failure("DISCONNECTED_STRUCTURAL_AGGREGATE", {"visited": visited.size(), "parts": part_by_id.size()})
	return Utils.success()

static func _validate_reduced_state(value: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(value, ["position", "orientation", "linear_velocity", "angular_velocity"])
	if not bool(checked.get("success", false)):
		return checked
	for field in ["position", "linear_velocity", "angular_velocity"]:
		checked = _validate_vec3(value.get(field))
		if not bool(checked.get("success", false)):
			return checked
	return _validate_quat(value.get("orientation"))

static func _validate_vec3(value) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or value.size() != 3:
		return Utils.failure("INVALID_STRUCTURAL_VECTOR3")
	for component in value:
		if not Utils.is_finite_number(component):
			return Utils.failure("INVALID_STRUCTURAL_VECTOR3")
	return Utils.success()

static func _validate_quat(value) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or value.size() != 4:
		return Utils.failure("INVALID_STRUCTURAL_QUATERNION")
	var norm_sq := 0.0
	for component in value:
		if not Utils.is_finite_number(component):
			return Utils.failure("INVALID_STRUCTURAL_QUATERNION")
		norm_sq += float(component) * float(component)
	if absf(norm_sq - 1.0) > 1.0e-9:
		return Utils.failure("NON_UNIT_STRUCTURAL_QUATERNION", {"norm_squared": norm_sq})
	return Utils.success()

static func _validate_spd_matrix3(value) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or value.size() != 3:
		return Utils.failure("INVALID_STRUCTURAL_INERTIA")
	for row in value:
		if typeof(row) != TYPE_ARRAY or row.size() != 3:
			return Utils.failure("INVALID_STRUCTURAL_INERTIA")
		for component in row:
			if not Utils.is_finite_number(component):
				return Utils.failure("INVALID_STRUCTURAL_INERTIA")
	for r in range(3):
		for c in range(3):
			if absf(float(value[r][c]) - float(value[c][r])) > MATRIX_TOLERANCE:
				return Utils.failure("NONSYMMETRIC_STRUCTURAL_INERTIA")
	var a := float(value[0][0])
	var det2 := a * float(value[1][1]) - float(value[0][1]) * float(value[1][0])
	var det3 := (
		float(value[0][0]) * (float(value[1][1]) * float(value[2][2]) - float(value[1][2]) * float(value[2][1]))
		- float(value[0][1]) * (float(value[1][0]) * float(value[2][2]) - float(value[1][2]) * float(value[2][0]))
		+ float(value[0][2]) * (float(value[1][0]) * float(value[2][1]) - float(value[1][1]) * float(value[2][0]))
	)
	if a <= 0.0 or det2 <= 0.0 or det3 <= 0.0:
		return Utils.failure("NONPOSITIVE_STRUCTURAL_INERTIA")
	return Utils.success()

static func _rotation_matrix(q: Quaternion) -> Array:
	var basis := Basis(q)
	return [
		[basis.x.x, basis.y.x, basis.z.x],
		[basis.x.y, basis.y.y, basis.z.y],
		[basis.x.z, basis.y.z, basis.z.z],
	]

static func _parallel_axis(mass: float, offset: Vector3) -> Array:
	var d2 := offset.length_squared()
	return [
		[mass * (d2 - offset.x * offset.x), -mass * offset.x * offset.y, -mass * offset.x * offset.z],
		[-mass * offset.y * offset.x, mass * (d2 - offset.y * offset.y), -mass * offset.y * offset.z],
		[-mass * offset.z * offset.x, -mass * offset.z * offset.y, mass * (d2 - offset.z * offset.z)],
	]

static func _rigid_point_jacobian(r: Vector3) -> Array:
	return [
		[1.0, 0.0, 0.0, 0.0, r.z, -r.y],
		[0.0, 1.0, 0.0, -r.z, 0.0, r.x],
		[0.0, 0.0, 1.0, r.y, -r.x, 0.0],
	]

static func _mat_mul(a: Array, b: Array) -> Array:
	var output := _zero3()
	for r in range(3):
		for c in range(3):
			var value := 0.0
			for k in range(3):
				value += float(a[r][k]) * float(b[k][c])
			output[r][c] = value
	return output

static func _mat_transpose(a: Array) -> Array:
	return [
		[float(a[0][0]), float(a[1][0]), float(a[2][0])],
		[float(a[0][1]), float(a[1][1]), float(a[2][1])],
		[float(a[0][2]), float(a[1][2]), float(a[2][2])],
	]

static func _mat_add(a: Array, b: Array) -> Array:
	var output := _zero3()
	for r in range(3):
		for c in range(3):
			output[r][c] = float(a[r][c]) + float(b[r][c])
	return output

static func _mat_vec(a: Array, v: Vector3) -> Vector3:
	return Vector3(
		float(a[0][0]) * v.x + float(a[0][1]) * v.y + float(a[0][2]) * v.z,
		float(a[1][0]) * v.x + float(a[1][1]) * v.y + float(a[1][2]) * v.z,
		float(a[2][0]) * v.x + float(a[2][1]) * v.y + float(a[2][2]) * v.z
	)

static func _zero3() -> Array:
	return [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]

static func _vec3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

static func _quat(value: Array) -> Quaternion:
	return Quaternion(float(value[0]), float(value[1]), float(value[2]), float(value[3])).normalized()

static func _arr3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

static func _arr4(value: Quaternion) -> Array:
	var q := _canonical_quat(value)
	return [q.x, q.y, q.z, q.w]

static func _canonical_quat(value: Quaternion) -> Quaternion:
	var q := value.normalized()
	if q.w < 0.0 or (is_zero_approx(q.w) and (q.z < 0.0 or (is_zero_approx(q.z) and (q.y < 0.0 or (is_zero_approx(q.y) and q.x < 0.0))))):
		return Quaternion(-q.x, -q.y, -q.z, -q.w)
	return q
