extends RefCounted

const PartitionAddressScript = preload(
	"res://scripts/simulation/partition/partition_address.gd"
)

const SCHEMA: String = "planet_simulator.cube_sphere_grid.v1"
const DEFAULT_SCHEME_ID: String = "cube_sphere"
const DEFAULT_SCHEME_REVISION: int = 1
const DEFAULT_BODY_FRAME_ID: String = "body/moon/fixed"
const DEFAULT_BODY_RADIUS_M: float = 1_737_400.0
const DEFAULT_ZONES_PER_FACE: int = 48
const DEFAULT_CHUNKS_PER_ZONE: int = 32

const FACE_POS_X: int = 0
const FACE_NEG_X: int = 1
const FACE_POS_Y: int = 2
const FACE_NEG_Y: int = 3
const FACE_POS_Z: int = 4
const FACE_NEG_Z: int = 5

var scheme_id: String = DEFAULT_SCHEME_ID
var scheme_revision: int = DEFAULT_SCHEME_REVISION
var body_frame_id: String = DEFAULT_BODY_FRAME_ID
var body_radius_m: float = DEFAULT_BODY_RADIUS_M
var zones_per_face: int = DEFAULT_ZONES_PER_FACE
var chunks_per_zone: int = DEFAULT_CHUNKS_PER_ZONE


func setup(config: Dictionary = {}) -> bool:
	scheme_id = String(config.get("scheme_id", DEFAULT_SCHEME_ID)).strip_edges().to_lower()
	scheme_revision = int(config.get("scheme_revision", DEFAULT_SCHEME_REVISION))
	body_frame_id = String(config.get("body_frame_id", DEFAULT_BODY_FRAME_ID)).strip_edges()
	body_radius_m = float(config.get("body_radius_m", DEFAULT_BODY_RADIUS_M))
	zones_per_face = int(config.get("zones_per_face", DEFAULT_ZONES_PER_FACE))
	chunks_per_zone = int(config.get("chunks_per_zone", DEFAULT_CHUNKS_PER_ZONE))
	return is_valid()


func is_valid() -> bool:
	return (
		not scheme_id.is_empty()
		and scheme_revision > 0
		and not body_frame_id.is_empty()
		and is_finite(body_radius_m)
		and body_radius_m > 0.0
		and zones_per_face > 0
		and chunks_per_zone > 0
	)


func create_descriptor() -> Dictionary:
	return {
		"schema": SCHEMA,
		"scheme_id": scheme_id,
		"scheme_revision": scheme_revision,
		"body_frame_id": body_frame_id,
		"body_radius_m": body_radius_m,
		"zones_per_face": zones_per_face,
		"chunks_per_zone": chunks_per_zone,
	}


func direction_to_face_uv(direction_value: Vector3) -> Vector3:
	# Face selection depends only on component ratios. Avoid normalization here:
	# it can introduce scale-dependent rounding close to cell boundaries.
	if direction_value.length_squared() <= 1.0e-24:
		return Vector3(float(FACE_POS_X), 0.0, 0.0)
	var direction := direction_value
	var ax: float = absf(direction.x)
	var ay: float = absf(direction.y)
	var az: float = absf(direction.z)

	if ax >= ay and ax >= az:
		if direction.x >= 0.0:
			return Vector3(float(FACE_POS_X), -direction.z / ax, direction.y / ax)
		return Vector3(float(FACE_NEG_X), direction.z / ax, direction.y / ax)

	if ay >= ax and ay >= az:
		if direction.y >= 0.0:
			return Vector3(float(FACE_POS_Y), direction.x / ay, -direction.z / ay)
		return Vector3(float(FACE_NEG_Y), direction.x / ay, direction.z / ay)

	if direction.z >= 0.0:
		return Vector3(float(FACE_POS_Z), direction.x / az, direction.y / az)
	return Vector3(float(FACE_NEG_Z), -direction.x / az, direction.y / az)


func face_uv_to_direction(face: int, u: float, v: float) -> Vector3:
	var direction: Vector3
	match face:
		FACE_POS_X:
			direction = Vector3(1.0, v, -u)
		FACE_NEG_X:
			direction = Vector3(-1.0, v, u)
		FACE_POS_Y:
			direction = Vector3(u, 1.0, -v)
		FACE_NEG_Y:
			direction = Vector3(u, -1.0, v)
		FACE_POS_Z:
			direction = Vector3(u, v, 1.0)
		FACE_NEG_Z:
			direction = Vector3(-u, v, -1.0)
		_:
			return Vector3.ZERO
	return direction.normalized()


func direction_to_cell(direction_value: Vector3) -> Dictionary:
	if direction_value.length_squared() <= 1.0e-24 or not is_valid():
		return {}
	var face_uv := direction_to_face_uv(direction_value)
	var face: int = int(face_uv.x)
	var normalized_u: float = clampf((face_uv.y + 1.0) * 0.5, 0.0, 0.999999999)
	var normalized_v: float = clampf((face_uv.z + 1.0) * 0.5, 0.0, 0.999999999)

	var zone_float_x: float = normalized_u * float(zones_per_face)
	var zone_float_y: float = normalized_v * float(zones_per_face)
	var zone_x: int = clampi(floori(zone_float_x), 0, zones_per_face - 1)
	var zone_y: int = clampi(floori(zone_float_y), 0, zones_per_face - 1)

	var zone_local_u: float = zone_float_x - float(zone_x)
	var zone_local_v: float = zone_float_y - float(zone_y)
	var chunk_x: int = clampi(
		floori(zone_local_u * float(chunks_per_zone)),
		0,
		chunks_per_zone - 1
	)
	var chunk_y: int = clampi(
		floori(zone_local_v * float(chunks_per_zone)),
		0,
		chunks_per_zone - 1
	)

	return {
		"face": face,
		"zone_x": zone_x,
		"zone_y": zone_y,
		"chunk_x": chunk_x,
		"chunk_y": chunk_y,
		"u": face_uv.y,
		"v": face_uv.z,
	}


func position_to_cell(position_in_body_frame: Vector3) -> Dictionary:
	return direction_to_cell(position_in_body_frame)


func create_partition_address(
	position_in_body_frame: Vector3,
	universe_id: String = PartitionAddressScript.DEFAULT_UNIVERSE_ID,
	instance_id: String = PartitionAddressScript.DEFAULT_INSTANCE_ID,
	space_id: String = PartitionAddressScript.DEFAULT_SPACE_ID
) -> Dictionary:
	var cell: Dictionary = position_to_cell(position_in_body_frame)
	if cell.is_empty():
		return {}
	return PartitionAddressScript.create_cube_sphere(
		int(cell["face"]),
		int(cell["zone_x"]),
		int(cell["zone_y"]),
		int(cell["chunk_x"]),
		int(cell["chunk_y"]),
		universe_id,
		space_id,
		scheme_id,
		instance_id,
		scheme_revision
	)


func contains_cell(address: Dictionary) -> bool:
	if not PartitionAddressScript.is_valid(address):
		return false
	if String(address.get("partition_scheme", "")) != scheme_id:
		return false
	if int(address.get("partition_scheme_revision", scheme_revision)) != scheme_revision:
		return false
	return (
		int(address.get("face", -1)) >= 0
		and int(address.get("face", -1)) < 6
		and int(address.get("zone_x", -1)) >= 0
		and int(address.get("zone_x", -1)) < zones_per_face
		and int(address.get("zone_y", -1)) >= 0
		and int(address.get("zone_y", -1)) < zones_per_face
		and (
			not PartitionAddressScript.has_chunk(address)
			or (
				int(address.get("chunk_x", -1)) >= 0
				and int(address.get("chunk_x", -1)) < chunks_per_zone
				and int(address.get("chunk_y", -1)) >= 0
				and int(address.get("chunk_y", -1)) < chunks_per_zone
			)
		)
	)


func zone_center_direction(face: int, zone_x: int, zone_y: int) -> Vector3:
	if not _zone_coordinates_valid(face, zone_x, zone_y):
		return Vector3.ZERO
	var u: float = (float(zone_x) + 0.5) / float(zones_per_face) * 2.0 - 1.0
	var v: float = (float(zone_y) + 0.5) / float(zones_per_face) * 2.0 - 1.0
	return face_uv_to_direction(face, u, v)


func chunk_center_direction(
	face: int,
	zone_x: int,
	zone_y: int,
	chunk_x: int,
	chunk_y: int
) -> Vector3:
	if (
		not _zone_coordinates_valid(face, zone_x, zone_y)
		or chunk_x < 0
		or chunk_x >= chunks_per_zone
		or chunk_y < 0
		or chunk_y >= chunks_per_zone
	):
		return Vector3.ZERO
	var total_cells: int = zones_per_face * chunks_per_zone
	var global_x: int = zone_x * chunks_per_zone + chunk_x
	var global_y: int = zone_y * chunks_per_zone + chunk_y
	var u: float = (float(global_x) + 0.5) / float(total_cells) * 2.0 - 1.0
	var v: float = (float(global_y) + 0.5) / float(total_cells) * 2.0 - 1.0
	return face_uv_to_direction(face, u, v)


func make_east(direction_value: Vector3) -> Vector3:
	if direction_value.length_squared() <= 1.0e-24:
		return Vector3.ZERO
	var direction := direction_value.normalized()
	var reference := Vector3.UP
	if absf(direction.dot(reference)) > 0.94:
		reference = Vector3.RIGHT
	return reference.cross(direction).normalized()


func make_north(direction_value: Vector3) -> Vector3:
	if direction_value.length_squared() <= 1.0e-24:
		return Vector3.ZERO
	var direction := direction_value.normalized()
	var east := make_east(direction)
	return direction.cross(east).normalized()


func offset_direction(
	center_direction_value: Vector3,
	east_offset_m: float,
	north_offset_m: float
) -> Vector3:
	if center_direction_value.length_squared() <= 1.0e-24 or not is_valid():
		return Vector3.ZERO
	var center_direction := center_direction_value.normalized()
	var east := make_east(center_direction)
	var north := center_direction.cross(east).normalized()
	var tangent_offset: Vector3 = east * east_offset_m + north * north_offset_m
	var distance_m: float = tangent_offset.length()
	if distance_m <= 1.0e-12:
		return center_direction
	var tangent_direction: Vector3 = tangent_offset / distance_m
	var angular_distance: float = distance_m / body_radius_m
	return (
		center_direction * cos(angular_distance)
		+ tangent_direction * sin(angular_distance)
	).normalized()


func offset_zone_cell(
	face: int,
	zone_x: int,
	zone_y: int,
	offset_x: int,
	offset_y: int
) -> Dictionary:
	if not _zone_coordinates_valid(face, zone_x, zone_y):
		return {}
	return _offset_face_cell(
		face,
		zone_x,
		zone_y,
		offset_x,
		offset_y,
		zones_per_face
	)


func offset_chunk_cell(
	face: int,
	zone_x: int,
	zone_y: int,
	chunk_x: int,
	chunk_y: int,
	offset_x: int,
	offset_y: int
) -> Dictionary:
	if (
		not _zone_coordinates_valid(face, zone_x, zone_y)
		or chunk_x < 0
		or chunk_x >= chunks_per_zone
		or chunk_y < 0
		or chunk_y >= chunks_per_zone
	):
		return {}
	var cells_per_face: int = zones_per_face * chunks_per_zone
	var global_x: int = zone_x * chunks_per_zone + chunk_x
	var global_y: int = zone_y * chunks_per_zone + chunk_y
	return _offset_face_cell(
		face,
		global_x,
		global_y,
		offset_x,
		offset_y,
		cells_per_face
	)


func offset_surface_position(
	position_in_body_frame: Vector3,
	east_offset_m: float,
	north_offset_m: float,
	altitude_offset_m: float = 0.0
) -> Vector3:
	if position_in_body_frame.length_squared() <= 1.0e-24:
		return Vector3.ZERO
	var direction := offset_direction(
		position_in_body_frame,
		east_offset_m,
		north_offset_m
	)
	return direction * (position_in_body_frame.length() + altitude_offset_m)


func angular_distance_m(a_value: Vector3, b_value: Vector3) -> float:
	if a_value.length_squared() <= 1.0e-24 or b_value.length_squared() <= 1.0e-24:
		return 0.0
	var a := a_value.normalized()
	var b := b_value.normalized()
	return acos(clampf(a.dot(b), -1.0, 1.0)) * body_radius_m


func get_nominal_zone_size_m() -> float:
	return body_radius_m * (PI * 0.5) / float(zones_per_face)


func get_nominal_chunk_size_m() -> float:
	return get_nominal_zone_size_m() / float(chunks_per_zone)


func _offset_face_cell(
	face: int,
	cell_x: int,
	cell_y: int,
	offset_x: int,
	offset_y: int,
	cells_per_face: int
) -> Dictionary:
	if face < 0 or face >= 6 or cells_per_face <= 0:
		return {}
	var u: float = (
		(float(cell_x + offset_x) + 0.5)
		/ float(cells_per_face)
		* 2.0
		- 1.0
	)
	var v: float = (
		(float(cell_y + offset_y) + 0.5)
		/ float(cells_per_face)
		* 2.0
		- 1.0
	)
	return direction_to_cell(face_uv_to_direction(face, u, v))


func _zone_coordinates_valid(face: int, zone_x: int, zone_y: int) -> bool:
	return (
		face >= 0
		and face < 6
		and zone_x >= 0
		and zone_x < zones_per_face
		and zone_y >= 0
		and zone_y < zones_per_face
	)
