extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const BrickAddressScript = preload("res://scripts/simulation/matter/contracts/matter_brick_address.gd")

const SCHEMA: String = "planet_simulator.matter_brick_mesh_data.v1"
const STATUS_EMPTY: String = "EMPTY"
const STATUS_READY: String = "READY"
const FIELDS: Array[String] = [
	"schema",
	"source_snapshot_checksum",
	"source_state_revision",
	"address",
	"origin_body_local_m",
	"iso_level_m",
	"status",
	"vertices",
	"normals",
	"colors",
	"indices",
	"triangle_count",
	"surface_bounds_min_m",
	"surface_bounds_max_m",
	"content_hash",
]
const HASH_POSITION_SCALE: float = 1000000.0
const HASH_NORMAL_SCALE: float = 1000000.0
const HASH_COLOR_SCALE: float = 1000000.0


static func create(
	source_snapshot_checksum: String,
	source_state_revision: int,
	address: Dictionary,
	origin_body_local_m: Vector3,
	iso_level_m: float,
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	indices: PackedInt32Array
) -> Dictionary:
	var triangle_count: int = int(indices.size() / 3)
	var bounds_min: Vector3 = Vector3.ZERO
	var bounds_max: Vector3 = Vector3.ZERO
	if not vertices.is_empty():
		bounds_min = vertices[0]
		bounds_max = vertices[0]
		for vertex in vertices:
			bounds_min = Vector3(
				minf(bounds_min.x, vertex.x),
				minf(bounds_min.y, vertex.y),
				minf(bounds_min.z, vertex.z)
			)
			bounds_max = Vector3(
				maxf(bounds_max.x, vertex.x),
				maxf(bounds_max.y, vertex.y),
				maxf(bounds_max.z, vertex.z)
			)
	var value: Dictionary = {
		"schema": SCHEMA,
		"source_snapshot_checksum": source_snapshot_checksum.strip_edges().to_lower(),
		"source_state_revision": source_state_revision,
		"address": address.duplicate(true),
		"origin_body_local_m": origin_body_local_m,
		"iso_level_m": iso_level_m,
		"status": STATUS_EMPTY if triangle_count == 0 else STATUS_READY,
		"vertices": vertices.duplicate(),
		"normals": normals.duplicate(),
		"colors": colors.duplicate(),
		"indices": indices.duplicate(),
		"triangle_count": triangle_count,
		"surface_bounds_min_m": bounds_min,
		"surface_bounds_max_m": bounds_max,
		"content_hash": "",
	}
	value["content_hash"] = _compute_content_hash(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	for field in FIELDS:
		if not value.has(field):
			return MatterUtilsScript.failure("MISSING_MATTER_MESH_FIELD", {"field": field})
	if value.size() != FIELDS.size():
		return MatterUtilsScript.failure("UNEXPECTED_MATTER_MESH_FIELD")
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return MatterUtilsScript.failure("UNSUPPORTED_MATTER_MESH_SCHEMA")
	if not MatterUtilsScript.is_lower_hex_64(value.get("source_snapshot_checksum")):
		return MatterUtilsScript.failure("INVALID_MATTER_MESH_SOURCE_CHECKSUM")
	if not MatterUtilsScript.is_json_integer(value.get("source_state_revision")) \
		or int(value["source_state_revision"]) < 0:
		return MatterUtilsScript.failure("INVALID_MATTER_MESH_SOURCE_REVISION")
	if typeof(value.get("address")) != TYPE_DICTIONARY \
		or not bool(BrickAddressScript.validate(value["address"]).get("success", false)):
		return MatterUtilsScript.failure("INVALID_MATTER_MESH_ADDRESS")
	if typeof(value.get("origin_body_local_m")) != TYPE_VECTOR3 \
		or not _is_finite_vector(value["origin_body_local_m"]):
		return MatterUtilsScript.failure("INVALID_MATTER_MESH_ORIGIN")
	if not MatterUtilsScript.is_finite_number(value.get("iso_level_m")):
		return MatterUtilsScript.failure("INVALID_MATTER_MESH_ISO_LEVEL")
	if typeof(value.get("status")) != TYPE_STRING \
		or String(value["status"]) not in [STATUS_EMPTY, STATUS_READY]:
		return MatterUtilsScript.failure("INVALID_MATTER_MESH_STATUS")
	if typeof(value.get("vertices")) != TYPE_PACKED_VECTOR3_ARRAY \
		or typeof(value.get("normals")) != TYPE_PACKED_VECTOR3_ARRAY \
		or typeof(value.get("colors")) != TYPE_PACKED_COLOR_ARRAY \
		or typeof(value.get("indices")) != TYPE_PACKED_INT32_ARRAY:
		return MatterUtilsScript.failure("INVALID_MATTER_MESH_ARRAY_TYPE")
	var vertices: PackedVector3Array = value["vertices"]
	var normals: PackedVector3Array = value["normals"]
	var colors: PackedColorArray = value["colors"]
	var indices: PackedInt32Array = value["indices"]
	if vertices.size() != normals.size() or vertices.size() != colors.size():
		return MatterUtilsScript.failure("MATTER_MESH_ATTRIBUTE_SIZE_MISMATCH")
	if indices.size() % 3 != 0:
		return MatterUtilsScript.failure("MATTER_MESH_INDEX_COUNT_NOT_TRIANGULATED")
	for vertex in vertices:
		if not _is_finite_vector(vertex):
			return MatterUtilsScript.failure("NON_FINITE_MATTER_MESH_VERTEX")
	for normal in normals:
		if not _is_finite_vector(normal) \
			or absf(normal.length_squared() - 1.0) > 0.0001:
			return MatterUtilsScript.failure("INVALID_MATTER_MESH_NORMAL")
	for color in colors:
		if not is_finite(color.r) or not is_finite(color.g) \
			or not is_finite(color.b) or not is_finite(color.a):
			return MatterUtilsScript.failure("NON_FINITE_MATTER_MESH_COLOR")
		if color.r < 0.0 or color.r > 1.0 or color.g < 0.0 or color.g > 1.0 \
			or color.b < 0.0 or color.b > 1.0 or color.a < 0.0 or color.a > 1.0:
			return MatterUtilsScript.failure("MATTER_MESH_COLOR_OUT_OF_RANGE")
	for index in indices:
		if index < 0 or index >= vertices.size():
			return MatterUtilsScript.failure("MATTER_MESH_INDEX_OUT_OF_RANGE")
	if not MatterUtilsScript.is_json_integer(value.get("triangle_count")) \
		or int(value["triangle_count"]) != int(indices.size() / 3):
		return MatterUtilsScript.failure("MATTER_MESH_TRIANGLE_COUNT_MISMATCH")
	if int(value["triangle_count"]) == 0:
		if String(value["status"]) != STATUS_EMPTY:
			return MatterUtilsScript.failure("NON_EMPTY_MATTER_MESH_STATUS_MISMATCH")
		if not vertices.is_empty() or not normals.is_empty() or not colors.is_empty():
			return MatterUtilsScript.failure("EMPTY_MATTER_MESH_HAS_ATTRIBUTES")
	else:
		if String(value["status"]) != STATUS_READY or vertices.is_empty():
			return MatterUtilsScript.failure("READY_MATTER_MESH_STATUS_MISMATCH")
	for field in ["surface_bounds_min_m", "surface_bounds_max_m"]:
		if typeof(value.get(field)) != TYPE_VECTOR3 or not _is_finite_vector(value[field]):
			return MatterUtilsScript.failure("INVALID_MATTER_MESH_BOUNDS", {"field": field})
	var expected_bounds: Dictionary = _bounds(vertices)
	if not _vectors_equal_approx(value["surface_bounds_min_m"], expected_bounds["minimum_m"]) \
		or not _vectors_equal_approx(value["surface_bounds_max_m"], expected_bounds["maximum_m"]):
		return MatterUtilsScript.failure("MATTER_MESH_BOUNDS_MISMATCH")
	if not MatterUtilsScript.is_lower_hex_64(value.get("content_hash")):
		return MatterUtilsScript.failure("INVALID_MATTER_MESH_CONTENT_HASH")
	if String(value["content_hash"]) != _compute_content_hash(value):
		return MatterUtilsScript.failure("MATTER_MESH_CONTENT_HASH_MISMATCH")
	return MatterUtilsScript.success()


static func world_vertex(value: Dictionary, vertex_index: int) -> Vector3:
	if not bool(validate(value).get("success", false)):
		return Vector3(INF, INF, INF)
	var vertices: PackedVector3Array = value["vertices"]
	if vertex_index < 0 or vertex_index >= vertices.size():
		return Vector3(INF, INF, INF)
	var origin: Vector3 = value["origin_body_local_m"]
	return origin + vertices[vertex_index]


static func collision_faces(value: Dictionary) -> PackedVector3Array:
	var result := PackedVector3Array()
	if not bool(validate(value).get("success", false)):
		return result
	var vertices: PackedVector3Array = value["vertices"]
	var indices: PackedInt32Array = value["indices"]
	for index in indices:
		result.append(vertices[index])
	return result


static func _compute_content_hash(value: Dictionary) -> String:
	var vertices: PackedVector3Array = value.get("vertices", PackedVector3Array())
	var normals: PackedVector3Array = value.get("normals", PackedVector3Array())
	var colors: PackedColorArray = value.get("colors", PackedColorArray())
	var indices: PackedInt32Array = value.get("indices", PackedInt32Array())
	var vertex_signature: Array = []
	var signature_count: int = mini(vertices.size(), mini(normals.size(), colors.size()))
	for index in range(signature_count):
		var vertex: Vector3 = vertices[index]
		var normal: Vector3 = normals[index]
		var color: Color = colors[index]
		vertex_signature.append([
			int(round(vertex.x * HASH_POSITION_SCALE)),
			int(round(vertex.y * HASH_POSITION_SCALE)),
			int(round(vertex.z * HASH_POSITION_SCALE)),
			int(round(normal.x * HASH_NORMAL_SCALE)),
			int(round(normal.y * HASH_NORMAL_SCALE)),
			int(round(normal.z * HASH_NORMAL_SCALE)),
			int(round(color.r * HASH_COLOR_SCALE)),
			int(round(color.g * HASH_COLOR_SCALE)),
			int(round(color.b * HASH_COLOR_SCALE)),
			int(round(color.a * HASH_COLOR_SCALE)),
		])
	var index_signature: Array = []
	for index in indices:
		index_signature.append(int(index))
	return MatterUtilsScript.payload_hash({
		"source_snapshot_checksum": String(value.get("source_snapshot_checksum", "")),
		"source_state_revision": int(value.get("source_state_revision", -1)),
		"address_id": String(Dictionary(value.get("address", {})).get("address_id", "")),
		"origin_body_local_mm": _quantized_vector(value.get("origin_body_local_m", Vector3.ZERO), 1000.0),
		"iso_level_um": int(round(float(value.get("iso_level_m", 0.0)) * 1000000.0)),
		"vertices": vertex_signature,
		"indices": index_signature,
	})


static func _bounds(vertices: PackedVector3Array) -> Dictionary:
	if vertices.is_empty():
		return {"minimum_m": Vector3.ZERO, "maximum_m": Vector3.ZERO}
	var minimum_m: Vector3 = vertices[0]
	var maximum_m: Vector3 = vertices[0]
	for vertex in vertices:
		minimum_m = Vector3(
			minf(minimum_m.x, vertex.x),
			minf(minimum_m.y, vertex.y),
			minf(minimum_m.z, vertex.z)
		)
		maximum_m = Vector3(
			maxf(maximum_m.x, vertex.x),
			maxf(maximum_m.y, vertex.y),
			maxf(maximum_m.z, vertex.z)
		)
	return {"minimum_m": minimum_m, "maximum_m": maximum_m}


static func _vectors_equal_approx(left: Vector3, right: Vector3) -> bool:
	return left.is_equal_approx(right)


static func _quantized_vector(value: Vector3, scale: float) -> Array:
	return [
		int(round(value.x * scale)),
		int(round(value.y * scale)),
		int(round(value.z * scale)),
	]


static func _is_finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)
