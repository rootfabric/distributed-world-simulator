extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const RequestScript = preload("res://scripts/simulation/matter/contracts/matter_mutation_request.gd")
const CellGridScript = preload("res://scripts/simulation/matter/spatial/matter_cell_grid.gd")
const BrickLayoutScript = preload("res://scripts/simulation/matter/spatial/matter_brick_layout.gd")

const BOUNDS_EPSILON_M: float = 0.000000001
const MUTATION_NARROW_BAND_SAMPLE_COUNT: int = 1


static func signed_distance_m(shape: Dictionary, point_m: Vector3) -> float:
	if not bool(_validate_shape(shape).get("success", false)) or not _finite_vector(point_m):
		return INF
	return signed_distance_validated(shape, point_m)


# Hot-loop variant. The caller must validate the immutable operation shape once
# before sampling a brick lattice.
static func signed_distance_validated(shape: Dictionary, point_m: Vector3) -> float:
	var kind: String = String(shape["kind"])
	var start_m: Vector3 = _vector3(shape["start_position_m"])
	var end_m: Vector3 = _vector3(shape["end_position_m"])
	if kind == "SPHERE":
		return point_m.distance_to(start_m) - float(shape["radius_m"])
	if kind == "CAPSULE":
		return _distance_to_segment(point_m, start_m, end_m) - float(shape["radius_m"])
	var half_extents_m: Vector3 = _vector3(shape["half_extents_m"])
	var center_m: Vector3 = (start_m + end_m) * 0.5
	var q: Vector3 = Vector3(
		absf(point_m.x - center_m.x),
		absf(point_m.y - center_m.y),
		absf(point_m.z - center_m.z)
	) - half_extents_m
	var outside: Vector3 = Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0))
	return outside.length() + minf(maxf(q.x, maxf(q.y, q.z)), 0.0)


static func bounds_m(shape: Dictionary, expansion_m: float = 0.0) -> Dictionary:
	if not bool(_validate_shape(shape).get("success", false)) \
		or not MatterUtilsScript.is_non_negative_number(expansion_m):
		return {}
	var start_m: Vector3 = _vector3(shape["start_position_m"])
	var end_m: Vector3 = _vector3(shape["end_position_m"])
	var extent_m: Vector3
	if String(shape["kind"]) == "BOX":
		extent_m = _vector3(shape["half_extents_m"]) + Vector3.ONE * expansion_m
	else:
		extent_m = Vector3.ONE * (float(shape["radius_m"]) + expansion_m)
	var minimum_m: Vector3 = Vector3(
		minf(start_m.x, end_m.x), minf(start_m.y, end_m.y), minf(start_m.z, end_m.z)
	) - extent_m
	var maximum_m: Vector3 = Vector3(
		maxf(start_m.x, end_m.x), maxf(start_m.y, end_m.y), maxf(start_m.z, end_m.z)
	) + extent_m
	return {
		"minimum_m": [minimum_m.x, minimum_m.y, minimum_m.z],
		"maximum_m": [maximum_m.x, maximum_m.y, maximum_m.z],
	}


static func mutation_band_m(grid_profile: Dictionary, cell_address: Dictionary) -> float:
	var spacing_m: float = BrickLayoutScript.sample_spacing_m(grid_profile, cell_address)
	if not MatterUtilsScript.is_positive_number(spacing_m):
		return 0.0
	return spacing_m * float(MUTATION_NARROW_BAND_SAMPLE_COUNT)


static func target_expansion_m(grid_profile: Dictionary, cell_address: Dictionary) -> float:
	var band_m: float = mutation_band_m(grid_profile, cell_address)
	if band_m <= 0.0:
		return 0.0
	return band_m + BrickLayoutScript.sample_spacing_m(grid_profile, cell_address) \
		* float(grid_profile["ghost_border_samples"])


static func affected_cell_addresses(
	grid_profile: Dictionary,
	shape: Dictionary,
	level: int
) -> Array:
	if level < 0 or level > int(grid_profile.get("max_level", -1)) \
		or not bool(_validate_shape(shape).get("success", false)):
		return []
	var root_address: Dictionary = CellGridScript.root_address(grid_profile)
	if root_address.is_empty():
		return []
	var root_bounds: Dictionary = CellGridScript.bounds_validated(grid_profile, root_address)
	var edge_m: float = float(root_bounds["edge_length_m"]) / float(1 << level)
	var root_center_m: Vector3 = _vector3(grid_profile["root_center_m"])
	var root_cell_address: Dictionary = CellGridScript.address_for_position(
		grid_profile, root_center_m, level
	)
	if root_cell_address.is_empty():
		return []
	var expansion_m: float = target_expansion_m(grid_profile, root_cell_address)
	if expansion_m <= 0.0:
		return []
	var shape_bounds: Dictionary = bounds_m(shape, expansion_m)
	if shape_bounds.is_empty():
		return []
	var root_minimum_m: Vector3 = _vector3(root_bounds["minimum_m"])
	var root_maximum_m: Vector3 = _vector3(root_bounds["maximum_m"])
	var minimum_m: Vector3 = _vector3(shape_bounds["minimum_m"])
	var maximum_m: Vector3 = _vector3(shape_bounds["maximum_m"])
	if maximum_m.x < root_minimum_m.x or maximum_m.y < root_minimum_m.y \
		or maximum_m.z < root_minimum_m.z or minimum_m.x > root_maximum_m.x \
		or minimum_m.y > root_maximum_m.y or minimum_m.z > root_maximum_m.z:
		return []
	minimum_m = Vector3(
		maxf(minimum_m.x, root_minimum_m.x),
		maxf(minimum_m.y, root_minimum_m.y),
		maxf(minimum_m.z, root_minimum_m.z)
	)
	maximum_m = Vector3(
		minf(maximum_m.x, root_maximum_m.x),
		minf(maximum_m.y, root_maximum_m.y),
		minf(maximum_m.z, root_maximum_m.z)
	)
	var count_per_axis: int = 1 << level
	var minimum_index: Vector3i = Vector3i(
		_clamped_index(minimum_m.x - BOUNDS_EPSILON_M, root_minimum_m.x, edge_m, count_per_axis),
		_clamped_index(minimum_m.y - BOUNDS_EPSILON_M, root_minimum_m.y, edge_m, count_per_axis),
		_clamped_index(minimum_m.z - BOUNDS_EPSILON_M, root_minimum_m.z, edge_m, count_per_axis)
	)
	var maximum_index: Vector3i = Vector3i(
		_clamped_index(maximum_m.x + BOUNDS_EPSILON_M, root_minimum_m.x, edge_m, count_per_axis),
		_clamped_index(maximum_m.y + BOUNDS_EPSILON_M, root_minimum_m.y, edge_m, count_per_axis),
		_clamped_index(maximum_m.z + BOUNDS_EPSILON_M, root_minimum_m.z, edge_m, count_per_axis)
	)
	var result_by_id: Dictionary = {}
	for z in range(minimum_index.z, maximum_index.z + 1):
		for y in range(minimum_index.y, maximum_index.y + 1):
			for x in range(minimum_index.x, maximum_index.x + 1):
				var center_m: Vector3 = root_minimum_m + Vector3(
					(float(x) + 0.5) * edge_m,
					(float(y) + 0.5) * edge_m,
					(float(z) + 0.5) * edge_m
				)
				var address: Dictionary = CellGridScript.address_for_position(
					grid_profile, center_m, level
				)
				if not address.is_empty():
					result_by_id[String(address["cell_id"])] = address
	var ids: Array = result_by_id.keys()
	ids.sort()
	var result: Array = []
	for cell_id in ids:
		result.append(Dictionary(result_by_id[cell_id]).duplicate(true))
	return result


static func affected_brick_addresses(
	grid_profile: Dictionary,
	shape: Dictionary,
	level: int
) -> Array:
	var result: Array = []
	for cell_address in affected_cell_addresses(grid_profile, shape, level):
		var address: Dictionary = BrickLayoutScript.brick_address(grid_profile, cell_address)
		if not address.is_empty():
			result.append(address)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("address_id", "")) < String(b.get("address_id", ""))
	)
	return result


static func _validate_shape(shape: Dictionary) -> Dictionary:
	return RequestScript.validate_shape(shape)


static func _distance_to_segment(point_m: Vector3, start_m: Vector3, end_m: Vector3) -> float:
	var segment: Vector3 = end_m - start_m
	var denominator: float = segment.length_squared()
	if denominator <= 0.000000000001:
		return point_m.distance_to(start_m)
	var factor: float = clampf((point_m - start_m).dot(segment) / denominator, 0.0, 1.0)
	return point_m.distance_to(start_m + segment * factor)


static func _clamped_index(value: float, root_minimum: float, edge_m: float, count: int) -> int:
	return clampi(int(floor((value - root_minimum) / edge_m)), 0, count - 1)


static func _finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


static func _vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
