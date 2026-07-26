extends RefCounted

# Deprecated compatibility facade. Production partition code uses
# scripts/simulation/partition/cube_sphere_grid.gd directly.
const CubeSphereGridScript = preload(
	"res://scripts/simulation/partition/cube_sphere_grid.gd"
)

const FACE_POS_X: int = CubeSphereGridScript.FACE_POS_X
const FACE_NEG_X: int = CubeSphereGridScript.FACE_NEG_X
const FACE_POS_Y: int = CubeSphereGridScript.FACE_POS_Y
const FACE_NEG_Y: int = CubeSphereGridScript.FACE_NEG_Y
const FACE_POS_Z: int = CubeSphereGridScript.FACE_POS_Z
const FACE_NEG_Z: int = CubeSphereGridScript.FACE_NEG_Z


static func direction_to_face_uv(direction_value: Vector3) -> Vector3:
	return _grid().direction_to_face_uv(direction_value)


static func face_uv_to_direction(face: int, u: float, v: float) -> Vector3:
	return _grid().face_uv_to_direction(face, u, v)


static func direction_to_address(
	direction_value: Vector3,
	zones_per_face: int,
	chunks_per_zone: int
) -> Dictionary:
	return _grid(zones_per_face, chunks_per_zone).direction_to_cell(direction_value)


static func zone_center_direction(
	face: int,
	zone_x: int,
	zone_y: int,
	zones_per_face: int
) -> Vector3:
	return _grid(zones_per_face).zone_center_direction(face, zone_x, zone_y)


static func chunk_center_direction(
	face: int,
	zone_x: int,
	zone_y: int,
	chunk_x: int,
	chunk_y: int,
	zones_per_face: int,
	chunks_per_zone: int
) -> Vector3:
	return _grid(zones_per_face, chunks_per_zone).chunk_center_direction(
		face,
		zone_x,
		zone_y,
		chunk_x,
		chunk_y
	)


static func make_east(direction_value: Vector3) -> Vector3:
	return _grid().make_east(direction_value)


static func make_north(direction_value: Vector3) -> Vector3:
	return _grid().make_north(direction_value)


static func offset_direction(
	center_direction_value: Vector3,
	east_offset_m: float,
	north_offset_m: float,
	body_radius_m: float
) -> Vector3:
	return _grid(-1, -1, body_radius_m).offset_direction(
		center_direction_value,
		east_offset_m,
		north_offset_m
	)


static func angular_distance_m(
	a_value: Vector3,
	b_value: Vector3,
	body_radius_m: float
) -> float:
	return _grid(-1, -1, body_radius_m).angular_distance_m(a_value, b_value)


static func _grid(
	zones_per_face: int = -1,
	chunks_per_zone: int = -1,
	body_radius_m: float = -1.0
):
	var grid = CubeSphereGridScript.new()
	var config: Dictionary = {}
	if zones_per_face > 0:
		config["zones_per_face"] = zones_per_face
	if chunks_per_zone > 0:
		config["chunks_per_zone"] = chunks_per_zone
	if body_radius_m > 0.0:
		config["body_radius_m"] = body_radius_m
	grid.setup(config)
	return grid
