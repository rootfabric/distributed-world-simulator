extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const CellAddressScript = preload("res://scripts/simulation/spatial/simulation_cell_address.gd")
const GridProfileScript = preload("res://scripts/simulation/matter/spatial/matter_spatial_grid_profile.gd")

const BOUNDS_SCHEMA: String = "planet_simulator.matter_cell_bounds.v1"
const BOUNDS_FIELDS: Array[String] = [
	"schema",
	"cell_address",
	"center_m",
	"half_extent_m",
	"minimum_m",
	"maximum_m",
	"edge_length_m",
	"checksum",
]
const CHILD_COUNT: int = 8
const POSITION_EPSILON_M: float = 0.000000001


static func root_address(grid_profile: Dictionary) -> Dictionary:
	if not bool(GridProfileScript.validate(grid_profile).get("success", false)):
		return {}
	return CellAddressScript.create(
		String(grid_profile["universe_id"]),
		String(grid_profile["instance_id"]),
		String(grid_profile["space_id"]),
		String(grid_profile["grid_id"]),
		int(grid_profile["grid_revision"]),
		String(grid_profile["root_id"]),
		[]
	)


static func validate_address(grid_profile: Dictionary, cell_address: Dictionary) -> Dictionary:
	if not bool(GridProfileScript.validate(grid_profile).get("success", false)):
		return MatterUtilsScript.failure("INVALID_MATTER_GRID_PROFILE")
	if not bool(CellAddressScript.validate(cell_address).get("success", false)):
		return MatterUtilsScript.failure("INVALID_MATTER_CELL_ADDRESS")
	for field in ["universe_id", "instance_id", "space_id", "grid_id", "grid_revision", "root_id"]:
		if cell_address[field] != grid_profile[field]:
			return MatterUtilsScript.failure("MATTER_CELL_GRID_MISMATCH", {"field": field})
	if int(cell_address["level"]) > int(grid_profile["max_level"]):
		return MatterUtilsScript.failure("MATTER_CELL_LEVEL_EXCEEDS_GRID")
	for child_index in cell_address["path"]:
		if int(child_index) < 0 or int(child_index) >= CHILD_COUNT:
			return MatterUtilsScript.failure("MATTER_CELL_REQUIRES_OCTREE_PATH")
	return MatterUtilsScript.success()


static func bounds(grid_profile: Dictionary, cell_address: Dictionary) -> Dictionary:
	if not bool(validate_address(grid_profile, cell_address).get("success", false)):
		return {}
	return bounds_validated(grid_profile, cell_address)


static func bounds_validated(grid_profile: Dictionary, cell_address: Dictionary) -> Dictionary:
	var center_m: Vector3 = _vector3(grid_profile["root_center_m"])
	var half_extent_m: float = float(grid_profile["root_half_extent_m"])
	for child_index_value in cell_address["path"]:
		var child_index: int = int(child_index_value)
		half_extent_m *= 0.5
		center_m += Vector3(
			half_extent_m if (child_index & 1) != 0 else -half_extent_m,
			half_extent_m if (child_index & 2) != 0 else -half_extent_m,
			half_extent_m if (child_index & 4) != 0 else -half_extent_m
		)
	var minimum_m: Vector3 = center_m - Vector3.ONE * half_extent_m
	var maximum_m: Vector3 = center_m + Vector3.ONE * half_extent_m
	var value: Dictionary = {
		"schema": BOUNDS_SCHEMA,
		"cell_address": cell_address.duplicate(true),
		"center_m": _array(center_m),
		"half_extent_m": half_extent_m,
		"minimum_m": _array(minimum_m),
		"maximum_m": _array(maximum_m),
		"edge_length_m": half_extent_m * 2.0,
		"checksum": "",
	}
	value["checksum"] = MatterUtilsScript.compute_checksum(value)
	return value


static func validate_bounds(value: Dictionary) -> Dictionary:
	var exact: Dictionary = MatterUtilsScript.validate_exact_fields(value, BOUNDS_FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != BOUNDS_SCHEMA:
		return MatterUtilsScript.failure("UNSUPPORTED_MATTER_CELL_BOUNDS_SCHEMA")
	if typeof(value.get("cell_address")) != TYPE_DICTIONARY \
		or not bool(CellAddressScript.validate(value["cell_address"]).get("success", false)):
		return MatterUtilsScript.failure("INVALID_MATTER_CELL_BOUNDS_ADDRESS")
	for field in ["center_m", "minimum_m", "maximum_m"]:
		if not MatterUtilsScript.is_vector3_array(value.get(field)):
			return MatterUtilsScript.failure("INVALID_MATTER_CELL_BOUNDS_VECTOR", {"field": field})
	for field in ["half_extent_m", "edge_length_m"]:
		if not MatterUtilsScript.is_positive_number(value.get(field)):
			return MatterUtilsScript.failure("INVALID_MATTER_CELL_BOUNDS_EXTENT", {"field": field})
	var center_m: Vector3 = _vector3(value["center_m"])
	var minimum_m: Vector3 = _vector3(value["minimum_m"])
	var maximum_m: Vector3 = _vector3(value["maximum_m"])
	var half_extent_m: float = float(value["half_extent_m"])
	if not _approximately_equal_vector(minimum_m, center_m - Vector3.ONE * half_extent_m) \
		or not _approximately_equal_vector(maximum_m, center_m + Vector3.ONE * half_extent_m):
		return MatterUtilsScript.failure("MATTER_CELL_BOUNDS_VECTOR_MISMATCH")
	if not MatterUtilsScript.approximately_equal(float(value["edge_length_m"]), half_extent_m * 2.0):
		return MatterUtilsScript.failure("MATTER_CELL_EDGE_LENGTH_MISMATCH")
	var safe: Dictionary = MatterUtilsScript.validate_json_safe(value, "$.matter_cell_bounds")
	if not bool(safe.get("success", false)):
		return safe
	return MatterUtilsScript.validate_checksum(value)


static func address_for_position(
	grid_profile: Dictionary,
	local_position_m: Vector3,
	level: int
) -> Dictionary:
	if not bool(GridProfileScript.validate(grid_profile).get("success", false)) \
		or level < 0 or level > int(grid_profile["max_level"]) \
		or not _is_finite_vector(local_position_m):
		return {}
	var root_center_m: Vector3 = _vector3(grid_profile["root_center_m"])
	var root_half_extent_m: float = float(grid_profile["root_half_extent_m"])
	var root_minimum_m: Vector3 = root_center_m - Vector3.ONE * root_half_extent_m
	var root_maximum_m: Vector3 = root_center_m + Vector3.ONE * root_half_extent_m
	if not _contains_closed(root_minimum_m, root_maximum_m, local_position_m):
		return {}
	var center_m: Vector3 = root_center_m
	var half_extent_m: float = root_half_extent_m
	var path: Array = []
	for _depth in range(level):
		var child_index: int = 0
		if local_position_m.x >= center_m.x:
			child_index |= 1
		if local_position_m.y >= center_m.y:
			child_index |= 2
		if local_position_m.z >= center_m.z:
			child_index |= 4
		path.append(child_index)
		half_extent_m *= 0.5
		center_m += Vector3(
			half_extent_m if (child_index & 1) != 0 else -half_extent_m,
			half_extent_m if (child_index & 2) != 0 else -half_extent_m,
			half_extent_m if (child_index & 4) != 0 else -half_extent_m
		)
	return CellAddressScript.create(
		String(grid_profile["universe_id"]),
		String(grid_profile["instance_id"]),
		String(grid_profile["space_id"]),
		String(grid_profile["grid_id"]),
		int(grid_profile["grid_revision"]),
		String(grid_profile["root_id"]),
		path
	)


static func child(cell_address: Dictionary, child_index: int, grid_profile: Dictionary) -> Dictionary:
	if child_index < 0 or child_index >= CHILD_COUNT \
		or not bool(validate_address(grid_profile, cell_address).get("success", false)):
		return {}
	var result: Dictionary = CellAddressScript.child(cell_address, child_index)
	return result if bool(validate_address(grid_profile, result).get("success", false)) else {}


static func parent(cell_address: Dictionary, grid_profile: Dictionary) -> Dictionary:
	if not bool(validate_address(grid_profile, cell_address).get("success", false)):
		return {}
	var result: Dictionary = CellAddressScript.parent(cell_address)
	if result.is_empty():
		return {}
	return result if bool(validate_address(grid_profile, result).get("success", false)) else {}


static func contains_position(
	grid_profile: Dictionary,
	cell_address: Dictionary,
	local_position_m: Vector3
) -> bool:
	var cell_bounds: Dictionary = bounds(grid_profile, cell_address)
	if cell_bounds.is_empty() or not _is_finite_vector(local_position_m):
		return false
	return _contains_closed(
		_vector3(cell_bounds["minimum_m"]),
		_vector3(cell_bounds["maximum_m"]),
		local_position_m
	)


static func _contains_closed(minimum_m: Vector3, maximum_m: Vector3, point_m: Vector3) -> bool:
	return point_m.x >= minimum_m.x - POSITION_EPSILON_M \
		and point_m.y >= minimum_m.y - POSITION_EPSILON_M \
		and point_m.z >= minimum_m.z - POSITION_EPSILON_M \
		and point_m.x <= maximum_m.x + POSITION_EPSILON_M \
		and point_m.y <= maximum_m.y + POSITION_EPSILON_M \
		and point_m.z <= maximum_m.z + POSITION_EPSILON_M


static func _is_finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


static func _approximately_equal_vector(a: Vector3, b: Vector3) -> bool:
	return MatterUtilsScript.approximately_equal(a.x, b.x) \
		and MatterUtilsScript.approximately_equal(a.y, b.y) \
		and MatterUtilsScript.approximately_equal(a.z, b.z)


static func _vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


static func _array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
