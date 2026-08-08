extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const BodyFixedPositionScript = preload("res://scripts/simulation/procedural/contracts/body_fixed_position.gd")
const SurfaceCellKeyScript = preload("res://scripts/simulation/procedural/contracts/surface_cell_key.gd")

const NEIGHBOR_WEST: String = "WEST"
const NEIGHBOR_EAST: String = "EAST"
const NEIGHBOR_SOUTH: String = "SOUTH"
const NEIGHBOR_NORTH: String = "NORTH"
const NEIGHBOR_DIRECTIONS: Array[String] = [NEIGHBOR_WEST, NEIGHBOR_EAST, NEIGHBOR_SOUTH, NEIGHBOR_NORTH]
const MIN_DIRECTION_LENGTH_SQUARED: float = 0.000000000000000001
const EDGE_EPSILON_FACTOR: float = 0.000001


func root_cells(body_id: String) -> Dictionary:
	if not GeoUtilsScript.is_canonical_id(body_id, 2):
		return GeoUtilsScript.failure("INVALID_SURFACE_CELL_BODY_ID")
	var cells: Array = []
	for face in SurfaceCellKeyScript.FACES:
		cells.append(SurfaceCellKeyScript.create(body_id, face, 0, 0, 0))
	return GeoUtilsScript.success({"cells": cells})


func body_position_to_cell(body_fixed_position: Dictionary, lod: int) -> Dictionary:
	var validation: Dictionary = BodyFixedPositionScript.validate(body_fixed_position)
	if not bool(validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_BODY_FIXED_POSITION", {"cause": validation.get("error_code", "")})
	return direction_to_cell(String(body_fixed_position["body_id"]), Array(body_fixed_position["position_m"]), lod)


func direction_to_cell(body_id: String, direction: Array, lod: int) -> Dictionary:
	if not GeoUtilsScript.is_canonical_id(body_id, 2):
		return GeoUtilsScript.failure("INVALID_SURFACE_CELL_BODY_ID")
	if not GeoUtilsScript.is_json_integer(lod) or lod < 0 or lod > SurfaceCellKeyScript.MAX_LOD:
		return GeoUtilsScript.failure("SURFACE_CELL_LOD_OUT_OF_RANGE")
	var face_uv: Dictionary = direction_to_face_uv(direction)
	if not bool(face_uv.get("success", false)):
		return face_uv
	var face: String = String(face_uv["details"]["face"])
	var u: float = float(face_uv["details"]["u"])
	var v: float = float(face_uv["details"]["v"])
	var side: int = 1 << lod
	var x: int = _unit_to_index((u + 1.0) * 0.5, side)
	var y: int = _unit_to_index((v + 1.0) * 0.5, side)
	var cell: Dictionary = SurfaceCellKeyScript.create(body_id, face, lod, x, y)
	var cell_validation: Dictionary = SurfaceCellKeyScript.validate(cell)
	if not bool(cell_validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_SURFACE_CELL_RESULT", {"cause": cell_validation.get("error_code", "")})
	return GeoUtilsScript.success({"cell": cell, "u": u, "v": v})


func direction_to_face_uv(direction: Array) -> Dictionary:
	if not GeoUtilsScript.is_vector3_array(direction):
		return GeoUtilsScript.failure("INVALID_CUBE_SPHERE_DIRECTION")
	var vector: Vector3 = _vector3(direction)
	if vector.length_squared() <= MIN_DIRECTION_LENGTH_SQUARED:
		return GeoUtilsScript.failure("ZERO_CUBE_SPHERE_DIRECTION")
	var ax: float = absf(vector.x)
	var ay: float = absf(vector.y)
	var az: float = absf(vector.z)
	var face: String
	var u: float
	var v: float
	if ax >= ay and ax >= az:
		if vector.x >= 0.0:
			face = "PX"
			u = vector.z / ax
			v = vector.y / ax
		else:
			face = "NX"
			u = -vector.z / ax
			v = vector.y / ax
	elif ay >= az:
		if vector.y >= 0.0:
			face = "PY"
			u = vector.z / ay
			v = -vector.x / ay
		else:
			face = "NY"
			u = vector.z / ay
			v = vector.x / ay
	else:
		if vector.z >= 0.0:
			face = "PZ"
			u = -vector.x / az
			v = vector.y / az
		else:
			face = "NZ"
			u = vector.x / az
			v = vector.y / az
	return GeoUtilsScript.success({
		"face": face,
		"u": clampf(u, -1.0, 1.0),
		"v": clampf(v, -1.0, 1.0),
	})


func face_uv_to_direction(face: String, u: float, v: float) -> Dictionary:
	if not SurfaceCellKeyScript.FACES.has(face):
		return GeoUtilsScript.failure("INVALID_SURFACE_CELL_FACE")
	if not is_finite(u) or not is_finite(v) or u < -1.0 or u > 1.0 or v < -1.0 or v > 1.0:
		return GeoUtilsScript.failure("CUBE_SPHERE_UV_OUT_OF_RANGE")
	var cube: Vector3 = _face_uv_to_cube(face, u, v)
	return GeoUtilsScript.success({"direction": _array3(cube.normalized())})


func cell_uv_bounds(cell: Dictionary) -> Dictionary:
	var validation: Dictionary = SurfaceCellKeyScript.validate(cell)
	if not bool(validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_SURFACE_CELL_KEY", {"cause": validation.get("error_code", "")})
	var side: float = float(1 << int(cell["lod"]))
	var u_min: float = -1.0 + 2.0 * float(cell["x"]) / side
	var u_max: float = -1.0 + 2.0 * float(int(cell["x"]) + 1) / side
	var v_min: float = -1.0 + 2.0 * float(cell["y"]) / side
	var v_max: float = -1.0 + 2.0 * float(int(cell["y"]) + 1) / side
	return GeoUtilsScript.success({
		"u_min": u_min,
		"u_max": u_max,
		"v_min": v_min,
		"v_max": v_max,
	})


func cell_center_direction(cell: Dictionary) -> Dictionary:
	var bounds: Dictionary = cell_uv_bounds(cell)
	if not bool(bounds.get("success", false)):
		return bounds
	var details: Dictionary = bounds["details"]
	return face_uv_to_direction(
		String(cell["face"]),
		(float(details["u_min"]) + float(details["u_max"])) * 0.5,
		(float(details["v_min"]) + float(details["v_max"])) * 0.5
	)


func cell_corner_directions(cell: Dictionary) -> Dictionary:
	var bounds: Dictionary = cell_uv_bounds(cell)
	if not bool(bounds.get("success", false)):
		return bounds
	var details: Dictionary = bounds["details"]
	var corners: Array = []
	for uv in [
		[details["u_min"], details["v_min"]],
		[details["u_max"], details["v_min"]],
		[details["u_max"], details["v_max"]],
		[details["u_min"], details["v_max"]],
	]:
		var result: Dictionary = face_uv_to_direction(String(cell["face"]), float(uv[0]), float(uv[1]))
		if not bool(result.get("success", false)):
			return result
		corners.append(Array(result["details"]["direction"]))
	return GeoUtilsScript.success({"corners": corners})


func parent(cell: Dictionary) -> Dictionary:
	var validation: Dictionary = SurfaceCellKeyScript.validate(cell)
	if not bool(validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_SURFACE_CELL_KEY", {"cause": validation.get("error_code", "")})
	var lod: int = int(cell["lod"])
	if lod == 0:
		return GeoUtilsScript.failure("SURFACE_CELL_ROOT_HAS_NO_PARENT")
	return GeoUtilsScript.success({
		"cell": SurfaceCellKeyScript.create(
			String(cell["body_id"]),
			String(cell["face"]),
			lod - 1,
			int(cell["x"]) >> 1,
			int(cell["y"]) >> 1
		),
	})


func children(cell: Dictionary) -> Dictionary:
	var validation: Dictionary = SurfaceCellKeyScript.validate(cell)
	if not bool(validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_SURFACE_CELL_KEY", {"cause": validation.get("error_code", "")})
	var lod: int = int(cell["lod"])
	if lod >= SurfaceCellKeyScript.MAX_LOD:
		return GeoUtilsScript.failure("SURFACE_CELL_MAX_LOD_HAS_NO_CHILDREN")
	var base_x: int = int(cell["x"]) << 1
	var base_y: int = int(cell["y"]) << 1
	var result: Array = []
	for offset in [[0, 0], [1, 0], [0, 1], [1, 1]]:
		result.append(SurfaceCellKeyScript.create(
			String(cell["body_id"]), String(cell["face"]), lod + 1,
			base_x + int(offset[0]), base_y + int(offset[1])
		))
	return GeoUtilsScript.success({"cells": result})


func neighbor(cell: Dictionary, direction: String) -> Dictionary:
	var validation: Dictionary = SurfaceCellKeyScript.validate(cell)
	if not bool(validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_SURFACE_CELL_KEY", {"cause": validation.get("error_code", "")})
	if not NEIGHBOR_DIRECTIONS.has(direction):
		return GeoUtilsScript.failure("INVALID_SURFACE_CELL_NEIGHBOR_DIRECTION")
	var lod: int = int(cell["lod"])
	var side: int = 1 << lod
	var x: int = int(cell["x"])
	var y: int = int(cell["y"])
	if direction == NEIGHBOR_WEST and x > 0:
		return GeoUtilsScript.success({"cell": SurfaceCellKeyScript.create(String(cell["body_id"]), String(cell["face"]), lod, x - 1, y)})
	if direction == NEIGHBOR_EAST and x + 1 < side:
		return GeoUtilsScript.success({"cell": SurfaceCellKeyScript.create(String(cell["body_id"]), String(cell["face"]), lod, x + 1, y)})
	if direction == NEIGHBOR_SOUTH and y > 0:
		return GeoUtilsScript.success({"cell": SurfaceCellKeyScript.create(String(cell["body_id"]), String(cell["face"]), lod, x, y - 1)})
	if direction == NEIGHBOR_NORTH and y + 1 < side:
		return GeoUtilsScript.success({"cell": SurfaceCellKeyScript.create(String(cell["body_id"]), String(cell["face"]), lod, x, y + 1)})

	var bounds_result: Dictionary = cell_uv_bounds(cell)
	if not bool(bounds_result.get("success", false)):
		return bounds_result
	var bounds: Dictionary = bounds_result["details"]
	var cell_width: float = 2.0 / float(side)
	var epsilon: float = maxf(0.000000000001, cell_width * EDGE_EPSILON_FACTOR)
	var u: float = (float(bounds["u_min"]) + float(bounds["u_max"])) * 0.5
	var v: float = (float(bounds["v_min"]) + float(bounds["v_max"])) * 0.5
	match direction:
		NEIGHBOR_WEST:
			u = -1.0 - epsilon
		NEIGHBOR_EAST:
			u = 1.0 + epsilon
		NEIGHBOR_SOUTH:
			v = -1.0 - epsilon
		NEIGHBOR_NORTH:
			v = 1.0 + epsilon
	var cube: Vector3 = _face_uv_to_cube(String(cell["face"]), u, v)
	var result: Dictionary = direction_to_cell(String(cell["body_id"]), _array3(cube), lod)
	if not bool(result.get("success", false)):
		return result
	return GeoUtilsScript.success({"cell": result["details"]["cell"]})


func _unit_to_index(unit_value: float, side: int) -> int:
	var scaled: float = clampf(unit_value, 0.0, 1.0) * float(side)
	if scaled >= float(side):
		return side - 1
	return clampi(int(floor(scaled)), 0, side - 1)


func _face_uv_to_cube(face: String, u: float, v: float) -> Vector3:
	match face:
		"PX":
			return Vector3(1.0, v, u)
		"NX":
			return Vector3(-1.0, v, -u)
		"PY":
			return Vector3(-v, 1.0, u)
		"NY":
			return Vector3(v, -1.0, u)
		"PZ":
			return Vector3(-u, v, 1.0)
		"NZ":
			return Vector3(u, v, -1.0)
	return Vector3.ZERO


func _vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _array3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
