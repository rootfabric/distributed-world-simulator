extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const BrickAddressScript = preload("res://scripts/simulation/matter/contracts/matter_brick_address.gd")
const GridProfileScript = preload("res://scripts/simulation/matter/spatial/matter_spatial_grid_profile.gd")
const CellGridScript = preload("res://scripts/simulation/matter/spatial/matter_cell_grid.gd")

const LATTICE_POSITION_EPSILON_M: float = 0.0000001


static func brick_address(grid_profile: Dictionary, cell_address: Dictionary) -> Dictionary:
	if not bool(CellGridScript.validate_address(grid_profile, cell_address).get("success", false)):
		return {}
	return BrickAddressScript.create(
		cell_address,
		int(cell_address["level"]),
		0,
		0,
		0
	)


static func validate_brick_address(grid_profile: Dictionary, address: Dictionary) -> Dictionary:
	if not bool(BrickAddressScript.validate(address).get("success", false)):
		return MatterUtilsScript.failure("INVALID_MATTER_BRICK_ADDRESS")
	if not bool(CellGridScript.validate_address(grid_profile, address["cell_address"]).get("success", false)):
		return MatterUtilsScript.failure("MATTER_BRICK_CELL_GRID_MISMATCH")
	if int(address["storage_level"]) != int(address["cell_address"]["level"]):
		return MatterUtilsScript.failure("MATTER_BRICK_STORAGE_LEVEL_MISMATCH")
	for field in ["brick_x", "brick_y", "brick_z"]:
		if int(address[field]) != 0:
			return MatterUtilsScript.failure("MW2_REQUIRES_ONE_BRICK_PER_CELL", {"field": field})
	return MatterUtilsScript.success()


static func sample_axis_count(grid_profile: Dictionary) -> int:
	return GridProfileScript.sample_axis_count(grid_profile)


static func sample_count(grid_profile: Dictionary) -> int:
	return GridProfileScript.sample_count(grid_profile)


static func sample_spacing_m(grid_profile: Dictionary, cell_address: Dictionary) -> float:
	var cell_bounds: Dictionary = CellGridScript.bounds(grid_profile, cell_address)
	if cell_bounds.is_empty():
		return INF
	return float(cell_bounds["edge_length_m"]) / float(grid_profile["brick_interior_resolution"])


static func flat_index(grid_profile: Dictionary, x: int, y: int, z: int) -> int:
	var axis_count: int = sample_axis_count(grid_profile)
	if x < 0 or y < 0 or z < 0 or x >= axis_count or y >= axis_count or z >= axis_count:
		return -1
	return x + axis_count * (y + axis_count * z)


static func coordinates_from_flat_index(grid_profile: Dictionary, index: int) -> Array:
	var axis_count: int = sample_axis_count(grid_profile)
	var total_count: int = axis_count * axis_count * axis_count
	if index < 0 or index >= total_count:
		return []
	var z: int = int(index / (axis_count * axis_count))
	var remainder: int = index - z * axis_count * axis_count
	var y: int = int(remainder / axis_count)
	var x: int = remainder - y * axis_count
	return [x, y, z]


static func sample_position_m(
	grid_profile: Dictionary,
	cell_address: Dictionary,
	x: int,
	y: int,
	z: int
) -> Vector3:
	if flat_index(grid_profile, x, y, z) < 0:
		return Vector3(INF, INF, INF)
	var cell_bounds: Dictionary = CellGridScript.bounds(grid_profile, cell_address)
	if cell_bounds.is_empty():
		return Vector3(INF, INF, INF)
	return sample_position_validated(grid_profile, cell_bounds, x, y, z)


static func sample_position_validated(
	grid_profile: Dictionary,
	cell_bounds: Dictionary,
	x: int,
	y: int,
	z: int
) -> Vector3:
	if flat_index(grid_profile, x, y, z) < 0:
		return Vector3(INF, INF, INF)
	var minimum_m: Vector3 = _vector3(cell_bounds["minimum_m"])
	var maximum_m: Vector3 = _vector3(cell_bounds["maximum_m"])
	var resolution: int = int(grid_profile["brick_interior_resolution"])
	var ghost: int = int(grid_profile["ghost_border_samples"])
	var spacing_m: float = float(cell_bounds["edge_length_m"]) / float(resolution)
	return Vector3(
		_axis_position(minimum_m.x, maximum_m.x, spacing_m, x - ghost, resolution),
		_axis_position(minimum_m.y, maximum_m.y, spacing_m, y - ghost, resolution),
		_axis_position(minimum_m.z, maximum_m.z, spacing_m, z - ghost, resolution)
	)


static func lattice_coordinates_for_position(
	grid_profile: Dictionary,
	cell_address: Dictionary,
	local_position_m: Vector3,
	tolerance_m: float = LATTICE_POSITION_EPSILON_M
) -> Array:
	if not is_finite(local_position_m.x) or not is_finite(local_position_m.y) \
		or not is_finite(local_position_m.z) or not is_finite(tolerance_m) or tolerance_m < 0.0:
		return []
	var cell_bounds: Dictionary = CellGridScript.bounds(grid_profile, cell_address)
	if cell_bounds.is_empty():
		return []
	return lattice_coordinates_for_position_validated(
		grid_profile, cell_bounds, local_position_m, tolerance_m
	)


static func lattice_coordinates_for_position_validated(
	grid_profile: Dictionary,
	cell_bounds: Dictionary,
	local_position_m: Vector3,
	tolerance_m: float = LATTICE_POSITION_EPSILON_M
) -> Array:
	if not is_finite(local_position_m.x) or not is_finite(local_position_m.y) \
		or not is_finite(local_position_m.z) or not is_finite(tolerance_m) or tolerance_m < 0.0:
		return []
	var minimum_m: Vector3 = _vector3(cell_bounds["minimum_m"])
	var resolution: int = int(grid_profile["brick_interior_resolution"])
	var ghost: int = int(grid_profile["ghost_border_samples"])
	var spacing_m: float = float(cell_bounds["edge_length_m"]) / float(resolution)
	var logical_x: int = int(round((local_position_m.x - minimum_m.x) / spacing_m))
	var logical_y: int = int(round((local_position_m.y - minimum_m.y) / spacing_m))
	var logical_z: int = int(round((local_position_m.z - minimum_m.z) / spacing_m))
	var result: Array = [logical_x + ghost, logical_y + ghost, logical_z + ghost]
	if flat_index(grid_profile, int(result[0]), int(result[1]), int(result[2])) < 0:
		return []
	var reconstructed: Vector3 = sample_position_validated(
		grid_profile, cell_bounds, int(result[0]), int(result[1]), int(result[2])
	)
	if reconstructed.distance_to(local_position_m) > tolerance_m:
		return []
	return result


static func interior_min_index(grid_profile: Dictionary) -> int:
	return int(grid_profile["ghost_border_samples"])


static func interior_max_index(grid_profile: Dictionary) -> int:
	return int(grid_profile["ghost_border_samples"]) \
		+ int(grid_profile["brick_interior_resolution"])


static func _axis_position(
	minimum_m: float,
	maximum_m: float,
	spacing_m: float,
	logical_index: int,
	resolution: int
) -> float:
	if logical_index == 0:
		return minimum_m
	if logical_index == resolution:
		return maximum_m
	return minimum_m + float(logical_index) * spacing_m


static func _vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
